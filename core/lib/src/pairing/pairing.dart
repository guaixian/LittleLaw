import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:grpc/grpc.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../generated/littlelaw.pb.dart' as pb;
import '../generated/littlelaw.pbgrpc.dart' as pbg;
import '../identity/identity.dart';
import '../oob/blob.dart';
import '../store/store.dart';
import '../transport/auth.dart';
import '../transport/transport.dart';

/// 待用户批准的配对请求(UI 弹出 PIN 核对框)。
class PairRequestEvent {
  PairRequestEvent({
    required this.requestId,
    required this.requester,
    required this.pin,
    required this.host,
    required this.completer,
  });

  final String requestId;
  final pb.DeviceInfo requester;
  final String pin;
  final String host;
  final Completer<bool> completer;
}

/// 主动发起配对的结果。
class PairResult {
  PairResult.accepted({
    required this.peerInfo,
    required this.token,
    required this.observedFingerprint,
  })  : accepted = true,
        message = '';

  PairResult.rejected(this.message)
      : accepted = false,
        peerInfo = null,
        token = null,
        observedFingerprint = null;

  final bool accepted;
  final pb.DeviceInfo? peerInfo;
  final String? token;
  final String? observedFingerprint;
  final String message;
}

/// 两阶段提交的暂存条目:用户已同意、令牌已签发,等发起方签名确认。
class _StagedPairing {
  _StagedPairing({
    required this.peer,
    required this.token,
    required this.nonce,
    required this.expiresAt,
  });
  final Peer peer;
  final String token;
  final String nonce;
  final DateTime expiresAt;
}

/// 配对管理:实现 PairingService 服务端,同时提供主动配对客户端。
///
/// 信任模型:TOFU + SAS。双方各自用对方指纹算同一个 6 位 PIN 并肉眼核对,
/// 通过后两阶段提交:响应方先暂存,发起方核验 TLS 观测指纹与宣称一致后
/// 回发身份私钥签名确认,响应方验签通过才落库——发起方发现中间人而放弃时,
/// 响应方不会留下可被冒充的信任条目。
class PairingManager extends pbg.PairingServiceBase {
  PairingManager({
    required this.identity,
    required this.store,
    required this.grpcPort,
    this.requestTimeout = const Duration(seconds: 60),
  });

  final Identity identity;
  final Store store;
  final Duration requestTimeout;

  /// gRPC 服务端口。final 改可变:47520 被占退化随机端口时,
  /// 引擎在 serveEngine 成功后回填实际绑定端口(配对广播用)。
  int grpcPort;

  /// 配对关系变化回调(引擎用于同步中转服务器的订阅列表)。
  void Function()? onPeersChanged;

  /// 解绑完成回调(引擎用于发 PeerRemoved 事件 + forceDisconnect)。
  void Function(String deviceId)? onPeerRemoved;

  void _notifyPeersChanged() => onPeersChanged?.call();

  static const _maxPending = 3;

  final _pending = <String, PairRequestEvent>{};
  final _staged = <String, _StagedPairing>{};
  final _requestsController = StreamController<PairRequestEvent>.broadcast();

  /// 每来源主机的请求频次(弹窗骚扰/槽位占满 DoS 防护)。
  final _requestRates = <String, List<int>>{};

  /// 配对请求事件(UI 监听并弹窗)。
  Stream<PairRequestEvent> get requests => _requestsController.stream;

  pb.DeviceInfo get myInfo => pb.DeviceInfo(
        deviceId: identity.deviceId,
        deviceName: identity.deviceName,
        platform: Identity.platformName(),
        certFingerprint: identity.fingerprint,
        port: grpcPort,
        protocolVersion: DiscoveryProtocol.version,
        deviceModel: identity.deviceModel,
        certDer: Identity.derOfCertPem(identity.certPem),
      );

  // ---------------------------------------------------------- 服务端

  bool _rateLimited(String host) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = (_requestRates[host] ??= <int>[])..add(now);
    list.removeWhere((t) => now - t > 30000); // 30s 窗口
    return list.length > 8;
  }

  @override
  Future<pb.PairResponse> requestPair(
      ServiceCall call, pb.PairRequest request) async {
    final requester = request.requester;
    final host = _remoteHost(call);
    // 基础校验。
    if (requester.deviceId.isEmpty ||
        requester.certFingerprint.length != 64 ||
        requester.deviceId == identity.deviceId) {
      return pb.PairResponse(accepted: false, message: 'invalid request');
    }
    if (requester.protocolVersion != DiscoveryProtocol.version) {
      return pb.PairResponse(
          accepted: false, message: 'protocol version mismatch');
    }
    // 请求方证书必须携带且与宣称指纹一致(两阶段提交的验签依据)。
    final certDer = requester.certDer;
    if (certDer.isEmpty || sha256.convert(certDer).toString() != requester.certFingerprint) {
      return pb.PairResponse(accepted: false, message: 'requester cert invalid');
    }
    if (_rateLimited(host)) {
      return pb.PairResponse(accepted: false, message: 'too many requests');
    }

    _sweepStaged();
    // 先淘汰过期挂起,再查容量(顺序颠倒会让 stale 占据槽位)。
    _pending.removeWhere((_, e) => e.completer.isCompleted);
    if (_pending.length >= _maxPending) {
      return pb.PairResponse(accepted: false, message: 'too many pending');
    }
    // 同一设备重复请求:踢掉旧的,以新的为准。
    final stale = _pending.entries
        .where((e) => e.value.requester.deviceId == requester.deviceId)
        .map((e) => e.key)
        .toList();
    for (final key in stale) {
      _pending.remove(key)?.completer.complete(false);
    }
    // requestId 冲突防护:同 ID 不同设备 → 拒绝,防"覆盖他人挂起请求 /
    // respond() 批准了覆盖者"的混乱代理。
    final conflict = _pending[request.requestId];
    if (request.requestId.isNotEmpty &&
        conflict != null &&
        conflict.requester.deviceId != requester.deviceId) {
      return pb.PairResponse(accepted: false, message: 'request id conflict');
    }
    // 已配对设备重新配对:指纹一致允许(幂等重配),指纹变化必须先解绑
    // (一次误点同意就静默替换指纹 = 身份劫持)。
    final existing = store.getPeer(requester.deviceId);
    if (existing != null &&
        existing.certFingerprint != requester.certFingerprint) {
      return pb.PairResponse(
          accepted: false, message: 'fingerprint changed; unpair first');
    }

    final pin = Identity.computeSasPin(
        identity.fingerprint, requester.certFingerprint);
    final event = PairRequestEvent(
      requestId: request.requestId.isNotEmpty
          ? request.requestId
          : const Uuid().v4(),
      requester: requester,
      pin: pin,
      host: host,
      completer: Completer<bool>(),
    );
    _pending[event.requestId] = event;
    _requestsController.add(event);

    var accepted = false;
    try {
      accepted = await event.completer.future.timeout(requestTimeout,
          onTimeout: () => false);
    } finally {
      _pending.remove(event.requestId);
    }
    if (!accepted) {
      return pb.PairResponse(accepted: false, message: 'rejected or timeout');
    }

    // 批准:签发令牌并【暂存】(不落库)——等发起方 ConfirmPair 签名确认。
    final token = Auth.newToken();
    final nonce = Auth.newToken().substring(0, 32);
    _staged[event.requestId] = _StagedPairing(
      peer: Peer(
        deviceId: requester.deviceId,
        deviceName: requester.deviceName,
        platform: requester.platform,
        certFingerprint: requester.certFingerprint,
        token: token,
        deviceModel: requester.deviceModel,
        certDerBase64: base64Encode(certDer),
        lastHost: host,
        lastPort: requester.port,
        pairedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      token: token,
      nonce: nonce,
      expiresAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    return pb.PairResponse(
      accepted: true,
      responder: myInfo,
      sessionToken: token.codeUnits,
      confirmNonce: nonce,
    );
  }

  void _sweepStaged() {
    final now = DateTime.now();
    _staged.removeWhere((_, s) => s.expiresAt.isBefore(now));
  }

  /// 两阶段提交第二阶段:验签通过才落库。
  /// 签名内容 "pair-confirm-v1|requestId|nonce|responderFingerprint",
  /// 用请求时携带的证书公钥验——纯转发者没有发起方私钥,无法伪造。
  @override
  Future<pb.PairConfirmResponse> confirmPair(
      ServiceCall call, pb.PairConfirmRequest request) async {
    final staged = _staged[request.requestId];
    if (staged == null) {
      return pb.PairConfirmResponse(ok: false, message: 'no staged pairing');
    }
    if (request.requesterId != staged.peer.deviceId) {
      return pb.PairConfirmResponse(ok: false, message: 'requester mismatch');
    }
    final certDer = base64Decode(staged.peer.certDerBase64);
    final msg = ascii.encode(
        'pair-confirm-v1|${request.requestId}|${staged.nonce}|${identity.fingerprint}');
    if (!Identity.verifyWithCertDer(certDer, msg, request.signature)) {
      return pb.PairConfirmResponse(ok: false, message: 'bad signature');
    }
    _staged.remove(request.requestId);
    // 落库令牌 = 轮换值(ECDH 派生),配对会话令牌不再兼任长期凭据。
    final rotated = rotateSessionToken(staged.token, certDer);
    final p = staged.peer;
    store.upsertPeer(Peer(
      deviceId: p.deviceId,
      deviceName: p.deviceName,
      platform: p.platform,
      certFingerprint: p.certFingerprint,
      token: rotated,
      deviceModel: p.deviceModel,
      certDerBase64: p.certDerBase64,
      lastHost: p.lastHost,
      lastPort: p.lastPort,
      pairedAtMs: p.pairedAtMs,
    ));
    _notifyPeersChanged();
    return pb.PairConfirmResponse(ok: true);
  }

  /// 发起方取消挂起的配对请求:完成对应的 completer 为拒绝。
  /// 未认证接口:只允许取消 requester_id 与挂起请求发起方一致的条目。
  @override
  Future<pb.PairCancelResponse> cancelPair(
      ServiceCall call, pb.PairCancelRequest request) async {
    final event = _pending[request.requestId];
    if (event != null && event.requester.deviceId == request.requesterId) {
      _pending.remove(request.requestId);
      event.completer.complete(false);
      return pb.PairCancelResponse(ok: true);
    }
    return pb.PairCancelResponse(ok: false);
  }

  @override
  Future<pb.UnpairResponse> unpair(
      ServiceCall call, pb.UnpairRequest request) async {
    final peer = Auth.verify(call, store);
    if (peer.deviceId != request.deviceId) {
      throw GrpcError.permissionDenied('device mismatch');
    }
    _wipePeer(peer.deviceId);
    return pb.UnpairResponse(ok: true);
  }

  /// 本地数据清除 + 墓碑会话 + 解绑出箱(Telegram 模式:双端各自归零)。
  /// 解绑会触发 onPeerRemoved(旧版不发事件,桌面会话列表残留到重启)。
  void _wipePeer(String deviceId, {bool queueNotice = false}) {
    final peer = store.getPeer(deviceId);
    final convId = Store.convIdFor(identity.deviceId, deviceId);
    final name = peer?.deviceName ?? deviceId.substring(0, 8);
    store.clearConversation(convId, removeConversation: false);
    if (queueNotice && peer != null) {
      // 对端离线没收到通知:进 outbox,链路恢复后引擎补发 UnpairNotice。
      store.queueUnpairNotice(peer);
    }
    store.compactOps(deviceId, 1 << 62);
    store.removePeer(deviceId);
    store.removeFromAllGroups(deviceId);
    // 墓碑系统消息(本地):会话保留在列表里,带解绑说明,可手动清除。
    store.ensureConversation(convId, deviceId);
    store.insertMessage(Message(
      msgId: const Uuid().v4(),
      convId: convId,
      senderId: identity.deviceId,
      lamport: store.nextLamport(convId),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      kind: Message.kindSystem,
      text: '已与 $name 解除配对,聊天记录已删除',
      sendState: Message.sendOk,
    ));
    onPeerRemoved?.call(deviceId);
  }

  /// 应用对端经信封送达的解绑通知(幂等:对端已不在 peers 表时跳过)。
  void applyRemoteUnpair(String peerId) {
    if (store.getPeer(peerId) == null) return;
    _wipePeer(peerId, queueNotice: false);
  }

  /// 解除配对(双端):通知对方 + 本地清除。
  Future<void> unpairWith(Peer peer) async {
    var notified = false;
    final ch = PeerChannel.connect(
      host: peer.lastHost ?? '',
      port: peer.lastPort ?? grpcPort,
      pinnedFingerprint: peer.certFingerprint,
      selfCertPem: identity.certPem,
    );
    try {
      final client = pbg.PairingServiceClient(ch.channel);
      await client.unpair(
        pb.UnpairRequest(deviceId: identity.deviceId),
        options: CallOptions(
            metadata: Auth.metadata(identity.deviceId, peer.token)),
      );
      notified = true;
    } catch (_) {
      // 对方不在线:走 outbox,链路恢复后补发解绑通知。
    } finally {
      await ch.shutdown();
    }
    _wipePeer(peer.deviceId, queueNotice: !notified);
  }

  // ---------------------------------------------------------- 客户端

  /// 用户响应配对请求(UI 调用)。
  void respond(String requestId, bool accept) {
    final event = _pending.remove(requestId);
    event?.completer.complete(accept);
  }

  /// 挂起的主动配对请求:目标设备 ID → (requestId, host, port)。
  final _outgoingRequests = <String, (String, String, int)>{};

  /// 主动向发现的设备发起配对。
  ///
  /// 返回的 PIN 需展示给用户,与对端弹窗中的 PIN 核对一致后再让对方点同意。
  Future<PairResult> requestPairWith(String host, int port,
      {String? targetDeviceId}) async {
    final requestId = const Uuid().v4();
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      _outgoingRequests[targetDeviceId] = (requestId, host, port);
    }
    try {
      final ch = PeerChannel.connect(
        host: host,
        port: port,
        selfCertPem: identity.certPem,
      );
      try {
        final client = pbg.PairingServiceClient(ch.channel);
        final resp = await client.requestPair(
          pb.PairRequest(requester: myInfo, requestId: requestId),
          options:
              CallOptions(timeout: requestTimeout + const Duration(seconds: 5)),
        );
        final observed = ch.observedFingerprint;
        if (!resp.accepted) {
          return PairResult.rejected(resp.message);
        }
        if (observed == null || observed != resp.responder.certFingerprint) {
          // TLS 观测指纹与宣称指纹不一致:中间人嫌疑,拒绝并【不确认】,
          // 响应方暂存条目超时作废,不会单边入账。
          return PairResult.rejected('fingerprint mismatch, possible MITM');
        }
        // 指纹核验通过:两阶段提交第二阶段——签名确认。
        final msg = ascii.encode(
            'pair-confirm-v1|$requestId|${resp.confirmNonce}|${resp.responder.certFingerprint}');
        final sig = identity.signMessage(msg);
        final confirm = await client.confirmPair(
          pb.PairConfirmRequest(
              requestId: requestId,
              requesterId: identity.deviceId,
              signature: sig),
          options: CallOptions(timeout: const Duration(seconds: 10)),
        );
        if (!confirm.ok) {
          return PairResult.rejected('confirm failed: ${confirm.message}');
        }
        final offerToken = String.fromCharCodes(resp.sessionToken);
        // 本地入账:令牌轮换为 ECDH 派生值(与响应方落库值一致)。
        final rotated =
            rotateSessionToken(offerToken, resp.responder.certDer);
        final r = resp.responder;
        store.upsertPeer(Peer(
          deviceId: r.deviceId,
          deviceName: r.deviceName,
          platform: r.platform,
          certFingerprint: r.certFingerprint,
          token: rotated,
          deviceModel: r.deviceModel,
          certDerBase64: base64Encode(r.certDer),
          lastHost: host,
          lastPort: port,
          pairedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
        _notifyPeersChanged();
        return PairResult.accepted(
          peerInfo: r,
          token: rotated,
          observedFingerprint: observed,
        );
      } finally {
        await ch.shutdown();
      }
    } finally {
      // 异常路径同样清理(旧版残留过期条目)。
      if (targetDeviceId != null) {
        _outgoingRequests.remove(targetDeviceId);
      }
    }
  }

  /// 主动方取消挂起的配对请求:通知对端完成挂起的 requestPair 为拒绝。
  /// 若对端恰好刚同意(竞态),调用方应再执行一次解绑回滚。
  Future<void> cancelOutgoingRequest(String targetDeviceId) async {
    final active = _outgoingRequests.remove(targetDeviceId);
    if (active == null) return;
    final (requestId, host, port) = active;
    final ch = PeerChannel.connect(
      host: host,
      port: port,
      selfCertPem: identity.certPem,
    );
    try {
      final client = pbg.PairingServiceClient(ch.channel);
      await client.cancelPair(
        pb.PairCancelRequest(
            requestId: requestId, requesterId: identity.deviceId),
        options: CallOptions(timeout: const Duration(seconds: 8)),
      );
    } catch (_) {
      // 对方不可达:其挂起请求最终会随超时作废,双方都不会入账。
    } finally {
      await ch.shutdown();
    }
  }

  /// 主动方在配对界面展示的 PIN(与对端弹窗同源)。
  String pinFor(String peerFingerprint) =>
      Identity.computeSasPin(identity.fingerprint, peerFingerprint);

  // ---------------------------------------------------------- OOB 引导包配对

  String? _pendingOfferToken;
  DateTime? _pendingOfferAt;

  /// (邀请方)开始一次远程邀请:生成共享令牌,由 app 层组装 offer 引导包
  /// (经二维码/NFC/复制粘贴带外传递)。令牌内存暂存,10 分钟有效。
  String beginRemoteOffer() {
    _pendingOfferToken = Auth.newToken();
    _pendingOfferAt = DateTime.now();
    return _pendingOfferToken!;
  }

  /// (受邀方)应用对方的 offer 引导包:信任对方并入账。
  /// 引导包经带外通道到达,指纹即为信任锚,无需 PIN。
  Peer acceptRemoteOffer(OobBlob blob,
      {Duration maxAge = const Duration(minutes: 10)}) {
    if (!blob.isOffer) throw ArgumentError('不是 offer 引导包');
    if (blob.age > maxAge) throw StateError('引导包已过期,请对方重新生成');
    if (blob.deviceId == identity.deviceId) {
      throw StateError('不能与本机配对');
    }
    // 受邀方记住 offer 令牌:若邀请方地址可达,用它自动回传应答。
    _pendingOfferTokenForDelivery = blob.token;
    final peer = Peer(
      deviceId: blob.deviceId,
      deviceName: blob.deviceName,
      platform: blob.platform,
      certFingerprint: blob.fingerprint,
      token: rotateSessionToken(blob.token, blob.certDer),
      deviceModel: blob.deviceModel,
      certDerBase64:
          blob.certDer.isEmpty ? '' : base64Encode(blob.certDer),
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    store.upsertPeer(peer);
    _notifyPeersChanged();
    return peer;
  }

  /// (邀请方)应用对方的 answer 引导包:校验令牌回显后入账。
  Peer acceptRemoteAnswer(OobBlob blob) {
    if (!blob.isAnswer) throw ArgumentError('不是 answer 引导包');
    if (blob.deviceId == identity.deviceId) {
      throw StateError('不能与本机配对');
    }
    final pending = _pendingOfferToken;
    final at = _pendingOfferAt;
    if (pending == null || at == null) {
      throw StateError('没有进行中的邀请,请先生成 offer');
    }
    if (DateTime.now().difference(at) > const Duration(minutes: 10)) {
      _pendingOfferToken = null;
      throw StateError('邀请已过期,请重新生成');
    }
    // 令牌原样回显 = 对方确实持有了我们的 offer(带外往返证明)。常量时间比较。
    if (!Auth.constantTimeEquals(blob.token, pending)) {
      throw StateError('令牌回显不匹配,这不是本次邀请的应答');
    }
    _pendingOfferToken = null;
    _pendingOfferAt = null;
    final peer = Peer(
      deviceId: blob.deviceId,
      deviceName: blob.deviceName,
      platform: blob.platform,
      certFingerprint: blob.fingerprint,
      token: rotateSessionToken(pending, blob.certDer),
      deviceModel: blob.deviceModel,
      certDerBase64:
          blob.certDer.isEmpty ? '' : base64Encode(blob.certDer),
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    store.upsertPeer(peer);
    _notifyPeersChanged();
    return peer;
  }

  /// 放弃进行中的邀请。
  void cancelRemoteOffer() {
    _pendingOfferToken = null;
    _pendingOfferAt = null;
  }

  // ---------------------------------------------------------- 一碰/一扫配对

  String? _tapToken;
  DateTime? _tapTokenAt;

  /// 有效窗口内的一次性物理通道令牌。
  static const _tapTokenTtl = Duration(minutes: 2);

  /// 开启免 PIN 配对窗口:生成 tap 令牌(随二维码/NFC 载荷带外传递)。
  /// 窗口期(2 分钟)内对方凭此令牌可完成配对;超时自动失效。
  String generateTapToken() {
    _tapToken = Auth.newToken();
    _tapTokenAt = DateTime.now();
    return _tapToken!;
  }

  bool _checkTapToken(String token) {
    final t = _tapToken;
    final at = _tapTokenAt;
    if (t == null || at == null) return false;
    if (DateTime.now().difference(at) > _tapTokenTtl) return false;
    return Auth.constantTimeEquals(token, t);
  }

  @override
  Future<pb.TapPairResponse> pairWithTap(
      ServiceCall call, pb.TapPairRequest request) async {
    final requester = request.requester;
    if (requester.deviceId.isEmpty ||
        requester.certFingerprint.length != 64 ||
        requester.deviceId == identity.deviceId ||
        requester.protocolVersion != DiscoveryProtocol.version) {
      return pb.TapPairResponse(accepted: false, message: 'invalid request');
    }
    if (!_checkTapToken(request.tapToken)) {
      return pb.TapPairResponse(
          accepted: false, message: 'tap token invalid or expired');
    }
    // 指纹变化防护:已配对 deviceId 重新 tap 必须先解绑。
    final existing = store.getPeer(requester.deviceId);
    if (existing != null &&
        existing.certFingerprint != requester.certFingerprint) {
      return pb.TapPairResponse(
          accepted: false, message: 'fingerprint changed; unpair first');
    }
    // 一次性:用后立即作废。
    _tapToken = null;
    _tapTokenAt = null;

    final offerToken = Auth.newToken();
    // 落库令牌 = ECDH 轮换值;响应里仍回原始 offer 令牌,对方轮换后一致。
    store.upsertPeer(Peer(
      deviceId: requester.deviceId,
      deviceName: requester.deviceName,
      platform: requester.platform,
      certFingerprint: requester.certFingerprint,
      token: rotateSessionToken(offerToken, requester.certDer),
      deviceModel: requester.deviceModel,
      certDerBase64: requester.certDer.isEmpty
          ? ''
          : base64Encode(requester.certDer),
      lastHost: _remoteHost(call),
      lastPort: requester.port,
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    _notifyPeersChanged();
    return pb.TapPairResponse(
      accepted: true,
      responder: myInfo,
      sessionToken: offerToken.codeUnits,
    );
  }

  /// (读取方)一碰/一扫配对:连接载荷中的地址,出示 tap 令牌。
  /// [expectedFingerprint] 来自二维码/NFC 载荷(展示方证书指纹):
  /// 连接直接 pin 到该指纹——中间人无法在免 PIN 通道里冒充展示方。
  Future<PairResult> pairViaTap(String host, int port, String tapToken,
      String expectedFingerprint) async {
    final ch = PeerChannel.connect(
      host: host,
      port: port,
      pinnedFingerprint: expectedFingerprint,
      selfCertPem: identity.certPem,
    );
    try {
      final client = pbg.PairingServiceClient(ch.channel);
      final resp = await client.pairWithTap(
        pb.TapPairRequest(requester: myInfo, tapToken: tapToken),
        options: CallOptions(timeout: const Duration(seconds: 15)),
      );
      final observed = ch.observedFingerprint;
      if (!resp.accepted) return PairResult.rejected(resp.message);
      if (observed == null || observed != resp.responder.certFingerprint) {
        return PairResult.rejected('fingerprint mismatch, possible MITM');
      }
      final offerToken = String.fromCharCodes(resp.sessionToken);
      final rotated = rotateSessionToken(offerToken, resp.responder.certDer);
      final r = resp.responder;
      store.upsertPeer(Peer(
        deviceId: r.deviceId,
        deviceName: r.deviceName,
        platform: r.platform,
        certFingerprint: r.certFingerprint,
        token: rotated,
        deviceModel: r.deviceModel,
        certDerBase64: base64Encode(r.certDer),
        lastHost: host,
        lastPort: port,
        pairedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      _notifyPeersChanged();
      return PairResult.accepted(
        peerInfo: r,
        token: rotated,
        observedFingerprint: observed,
      );
    } finally {
      await ch.shutdown();
    }
  }

  // ---------------------------------------------------- 应答自动回传

  /// 收到的远程应答(answer 引导包编码串),由 app 层应用到 WebRTC。
  final _answerDeliveries = StreamController<String>.broadcast();
  Stream<String> get answerDeliveries => _answerDeliveries.stream;

  /// 当前进行中的远程邀请令牌(供中转服务器回退解密受邀方应答)。
  String? get pendingRemoteOfferToken => _pendingOfferToken;

  /// 受邀方暂存的 offer 令牌(应答回传加密用;暴露给中转客户端)。
  String? get pendingDeliveryToken => _pendingOfferTokenForDelivery;

  /// 注入一份经任意通道到达的远程应答(统一走 WebRTC 应用路径)。
  void noteRemoteAnswer(String answerBlob) => _answerDeliveries.add(answerBlob);

  @override
  Future<pb.DeliverAnswerResponse> deliverAnswer(
      ServiceCall call, pb.DeliverAnswerRequest request) async {
    final pending = _pendingOfferToken;
    final at = _pendingOfferAt;
    if (pending == null ||
        at == null ||
        DateTime.now().difference(at) > const Duration(minutes: 10)) {
      return pb.DeliverAnswerResponse(
          ok: false, message: 'no pending invite or expired');
    }
    // offer_token = 持有邀请二维码的物理证明。
    if (!Auth.constantTimeEquals(request.offerToken, pending)) {
      return pb.DeliverAnswerResponse(ok: false, message: 'token mismatch');
    }
    // 只验证应答包格式合法,不做入账/消费——入账与链路建立统一由
    // WebRTC 层经 answerDeliveries 事件一次性完成(避免双重消费令牌)。
    try {
      OobBlob.decode(request.answerBlob);
    } catch (e) {
      return pb.DeliverAnswerResponse(ok: false, message: '$e');
    }
    _answerDeliveries.add(request.answerBlob);
    return pb.DeliverAnswerResponse(ok: true);
  }

  /// (受邀方)把 answer 引导包自动回传给邀请方。
  /// [inviterFingerprint] 邀请方证书指纹(来自 offer 引导包):回传连接
  /// 必须 pin 到它——offer 令牌是共享秘密,发给任意 TLS 终结者会被截获
  /// 并注入伪造 answer。
  Future<void> deliverAnswerTo(String host, int port, String answerBlob,
      String inviterFingerprint) async {
    final ch = PeerChannel.connect(
      host: host,
      port: port,
      pinnedFingerprint:
          inviterFingerprint.isEmpty ? null : inviterFingerprint,
      selfCertPem: identity.certPem,
    );
    try {
      final client = pbg.PairingServiceClient(ch.channel);
      final pending = _pendingOfferTokenForDelivery ?? '';
      final resp = await client.deliverAnswer(
        pb.DeliverAnswerRequest(
            requester: myInfo, offerToken: pending, answerBlob: answerBlob),
        options: CallOptions(timeout: const Duration(seconds: 15)),
      );
      if (!resp.ok) throw StateError(resp.message);
    } finally {
      await ch.shutdown();
    }
  }

  /// 受邀方侧暂存:加入邀请时收到的 offer 令牌(deliverAnswerTo 出示用)。
  String? _pendingOfferTokenForDelivery;

  String _remoteHost(ServiceCall call) {
    // grpc-dart 不直接暴露远端地址,配对回显用途,尽力而为。
    final authority = call.clientMetadata?[':authority'];
    if (authority == null) return '';
    final idx = authority.lastIndexOf(':');
    return idx > 0 ? authority.substring(0, idx) : authority;
  }

  Future<void> dispose() async {
    for (final e in _pending.values) {
      e.completer.complete(false);
    }
    _pending.clear();
    await _answerDeliveries.close();
    await _requestsController.close();
  }

  // ---------------------------------------------------- 令牌轮换

  /// 配对令牌轮换:sha256("ll-token-v2|" + ECDH(我方私钥, 对方证书公钥)
  /// + "|" + 原令牌)。双方各自独立计算结果一致(对称 ECDH),
  /// 纯截获 QR/令牌的攻击者没有身份私钥,推不出轮换值——
  /// 带外泄露的令牌不再等于长期会话凭据。
  String rotateSessionToken(String offerToken, List<int> peerCertDer) {
    List<int> material = utf8.encode('|$offerToken');
    if (peerCertDer.isNotEmpty) {
      try {
        final pub = Identity.ecPublicKeyOfCertDer(peerCertDer);
        final priv = Identity.ecPrivateKeyOfPem(identity.keyPem);
        final agreement = ECDHBasicAgreement()..init(priv);
        final shared = agreement.calculateAgreement(pub);
        material = [...bigToFixedBytes(shared, 32), ...material];
      } catch (_) {
        // 证书解析失败:退回令牌原文派生(兼容无证书的旧引导包)。
      }
    }
    return sha256.convert(utf8.encode('ll-token-v2|') + material).toString();
  }
}

/// 大整数转定长字节(高位补零)。
Uint8List bigToFixedBytes(BigInt v, int length) {
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final raw = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16)
  ]);
  if (raw.length > length) {
    return Uint8List.fromList(raw.sublist(raw.length - length));
  }
  final out = Uint8List(length);
  out.setRange(length - raw.length, length, raw);
  return out;
}

/// 发现层协议常量(避免循环依赖)。
class DiscoveryProtocol {
  /// v2:发现层宣告强制签名 + 时间戳新鲜度校验(v1 明文已弃用)。
  static const version = '2';
}
