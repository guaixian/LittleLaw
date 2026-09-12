import 'dart:async';

import 'package:grpc/grpc.dart';
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

/// 配对管理:实现 PairingService 服务端,同时提供主动配对客户端。
///
/// 信任模型:TOFU + SAS。双方各自用对方指纹算同一个 6 位 PIN 并肉眼核对,
/// 通过后被请求方签发共享会话令牌,双方写入 trusted_peers。
class PairingManager extends pbg.PairingServiceBase {
  PairingManager({
    required this.identity,
    required this.store,
    required this.grpcPort,
    this.requestTimeout = const Duration(seconds: 60),
  });

  final Identity identity;
  final Store store;
  final int grpcPort;
  final Duration requestTimeout;

  /// 配对关系变化回调(引擎用于同步中转服务器的订阅列表)。
  void Function()? onPeersChanged;

  void _notifyPeersChanged() => onPeersChanged?.call();

  static const _maxPending = 3;

  final _pending = <String, PairRequestEvent>{};
  final _requestsController = StreamController<PairRequestEvent>.broadcast();

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
      );

  // ---------------------------------------------------------- 服务端

  @override
  Future<pb.PairResponse> requestPair(
      ServiceCall call, pb.PairRequest request) async {
    final requester = request.requester;
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

    final pin = Identity.computeSasPin(
        identity.fingerprint, requester.certFingerprint);
    final event = PairRequestEvent(
      requestId: const Uuid().v4(),
      requester: requester,
      pin: pin,
      host: _remoteHost(call),
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

    // 批准:签发令牌,写入可信设备。
    final token = Auth.newToken();
    store.upsertPeer(Peer(
      deviceId: requester.deviceId,
      deviceName: requester.deviceName,
      platform: requester.platform,
      certFingerprint: requester.certFingerprint,
      token: token,
      deviceModel: requester.deviceModel,
      lastHost: _remoteHost(call),
      lastPort: requester.port,
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    _notifyPeersChanged();
    return pb.PairResponse(
      accepted: true,
      responder: myInfo,
      sessionToken: token.codeUnits,
    );
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

  /// 本地数据一并清除(Telegram 模式:双方各自调用后双端归零)。
  void _wipePeer(String deviceId) {
    final convId = Store.convIdFor(identity.deviceId, deviceId);
    store.clearConversation(convId);
    store.compactOps(deviceId, 1 << 62);
    store.removePeer(deviceId);
  }

  /// 解除配对(双端):通知对方 + 本地清除。
  Future<void> unpairWith(Peer peer) async {
    final ch = PeerChannel.connect(
      host: peer.lastHost ?? '',
      port: peer.lastPort ?? grpcPort,
      pinnedFingerprint: peer.certFingerprint,
    );
    try {
      final client = pbg.PairingServiceClient(ch.channel);
      await client.unpair(
        pb.UnpairRequest(deviceId: identity.deviceId),
        options: CallOptions(
            metadata: Auth.metadata(identity.deviceId, peer.token)),
      );
    } catch (_) {
      // 对方不在线:本地照常清除,对方重连时令牌失效即等同解绑。
    } finally {
      await ch.shutdown();
    }
    _wipePeer(peer.deviceId);
  }

  // ---------------------------------------------------------- 客户端

  /// 用户响应配对请求(UI 调用)。
  void respond(String requestId, bool accept) {
    final event = _pending.remove(requestId);
    event?.completer.complete(accept);
  }

  /// 主动向发现的设备发起配对。
  ///
  /// 返回的 PIN 需展示给用户,与对端弹窗中的 PIN 核对一致后再让对方点同意。
  Future<PairResult> requestPairWith(String host, int port) async {
    final ch = PeerChannel.connect(host: host, port: port);
    try {
      final client = pbg.PairingServiceClient(ch.channel);
      final resp = await client.requestPair(
        pb.PairRequest(requester: myInfo),
        options: CallOptions(timeout: requestTimeout + const Duration(seconds: 5)),
      );
      final observed = ch.observedFingerprint;
      if (!resp.accepted) {
        return PairResult.rejected(resp.message);
      }
      if (observed == null || observed != resp.responder.certFingerprint) {
        // TLS 观测指纹与宣称指纹不一致:中间人嫌疑,拒绝入账。
        return PairResult.rejected('fingerprint mismatch, possible MITM');
      }
      final token = String.fromCharCodes(resp.sessionToken);
      // 我方同样入账:对方成为可信设备。
      store.upsertPeer(Peer(
        deviceId: resp.responder.deviceId,
        deviceName: resp.responder.deviceName,
        platform: resp.responder.platform,
        certFingerprint: resp.responder.certFingerprint,
        token: token,
        deviceModel: resp.responder.deviceModel,
        lastHost: host,
        lastPort: port,
        pairedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      _notifyPeersChanged();
      return PairResult.accepted(
        peerInfo: resp.responder,
        token: token,
        observedFingerprint: observed,
      );
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
      token: blob.token,
      deviceModel: blob.deviceModel,
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
    // 令牌原样回显 = 对方确实持有了我们的 offer(带外往返证明)。
    if (blob.token != pending) {
      throw StateError('令牌回显不匹配,这不是本次邀请的应答');
    }
    _pendingOfferToken = null;
    _pendingOfferAt = null;
    final peer = Peer(
      deviceId: blob.deviceId,
      deviceName: blob.deviceName,
      platform: blob.platform,
      certFingerprint: blob.fingerprint,
      token: blob.token,
      deviceModel: blob.deviceModel,
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
    // 一次性:用后立即作废。
    _tapToken = null;
    _tapTokenAt = null;

    final token = Auth.newToken();
    store.upsertPeer(Peer(
      deviceId: requester.deviceId,
      deviceName: requester.deviceName,
      platform: requester.platform,
      certFingerprint: requester.certFingerprint,
      token: token,
      deviceModel: requester.deviceModel,
      lastHost: _remoteHost(call),
      lastPort: requester.port,
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    _notifyPeersChanged();
    return pb.TapPairResponse(
      accepted: true,
      responder: myInfo,
      sessionToken: token.codeUnits,
    );
  }

  /// (读取方)一碰/一扫配对:连接载荷中的地址,出示 tap 令牌。
  Future<PairResult> pairViaTap(String host, int port, String tapToken) async {
    final ch = PeerChannel.connect(host: host, port: port);
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
      final token = String.fromCharCodes(resp.sessionToken);
      store.upsertPeer(Peer(
        deviceId: resp.responder.deviceId,
        deviceName: resp.responder.deviceName,
        platform: resp.responder.platform,
        certFingerprint: resp.responder.certFingerprint,
        token: token,
        deviceModel: resp.responder.deviceModel,
        lastHost: host,
        lastPort: port,
        pairedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      _notifyPeersChanged();
      return PairResult.accepted(
        peerInfo: resp.responder,
        token: token,
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
  Future<void> deliverAnswerTo(String host, int port, String answerBlob) async {
    final ch = PeerChannel.connect(host: host, port: port);
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
}

/// 发现层协议常量(避免循环依赖)。
class DiscoveryProtocol {
  static const version = '1';
}
