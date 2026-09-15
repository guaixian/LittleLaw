import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../crypto/secure_codec.dart';
import '../identity/identity.dart';
import '../store/store.dart';
import '../util.dart';

/// 经服务器收到的信令(已解密)。
class RendezvousSignal {
  RendezvousSignal({required this.fromPeerId, required this.payload});
  final String fromPeerId;
  final Map<String, dynamic> payload; // {"sdp":..., "candidates":[...]}
}

/// 经服务器收到的离线信封(已解密,反序列化前)。
class RendezvousMail {
  RendezvousMail({
    required this.id,
    required this.fromPeerId,
    required this.envelopeBytes,
  });
  final int id;
  final String fromPeerId;
  final Uint8List envelopeBytes;
}

/// 对端上线事件(可携带公网直连端点)。
class RendezvousPeerOnline {
  RendezvousPeerOnline({required this.id, this.endpoint});
  final String id;
  final String? endpoint; // host:port(对端 UPnP 映射,可空)
}

/// Rendezvous 客户端:连接可选的公网中转服务器。
///
/// 职责:注册(ECDSA 挑战认证)、presence 订阅、信令收发(密文)、
/// 离线邮箱推拉(密文)。服务器只见设备 ID 与密文;
/// 没有配置服务器时本类完全不工作,引擎行为与之前一致。
class RendezvousClient {
  RendezvousClient({
    required this.identity,
    required this.store,
    required this.url,
    this.endpoint,
  });

  /// 内置公共中转服务器(默认;可在设置中改为自建地址或 off 关闭)。
  static const defaultUrl = 'wss://littlelaw.joywiki.cc/ws';

  final Identity identity;
  final Store store;
  final String url; // ws://host:port/ws 或 wss://domain/ws

  /// 本机公网直连端点(UPnP 映射,注册时上报,可空)。
  String? endpoint;

  /// 回退令牌来源:信令来自未入账设备(远程配对的受邀方)时,
  /// 用进行中的邀请令牌尝试解密(典型场景:一扫即成的应答推回)。
  String? Function()? fallbackTokenProvider;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  /// 邮箱轮询:链路僵死时兜底(双路投递的接收端),15s 一次。
  Timer? _mailPollTimer;

  void _startMailPolling() {
    _mailPollTimer?.cancel();
    _mailPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_up) fetchMailbox();
    });
  }
  Duration _backoff = const Duration(seconds: 1);
  bool _stopping = false;

  final _peerOnline = StreamController<String>.broadcast();
  final _peerOnlineEx = StreamController<RendezvousPeerOnline>.broadcast();
  final _peerOffline = StreamController<String>.broadcast();
  final _signals = StreamController<RendezvousSignal>.broadcast();
  final _mail = StreamController<RendezvousMail>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _pairAnswers = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();

  Stream<String> get peerOnline => _peerOnline.stream;

  /// 对端上线(含公网端点,如有)。
  Stream<RendezvousPeerOnline> get peerOnlineEx => _peerOnlineEx.stream;
  Stream<String> get peerOffline => _peerOffline.stream;
  Stream<RendezvousSignal> get signals => _signals.stream;
  Stream<RendezvousMail> get mail => _mail.stream;
  Stream<bool> get connectionState => _connected.stream;

  /// 经服务器到达的"配对应答"引导包(受邀方一扫即成的推回)。
  Stream<String> get pairAnswers => _pairAnswers.stream;

  /// 服务器 error 帧(认证失败/邮箱满等)。旧版全部静默吞掉:
  /// 认证失败 → 无限静默重连;邮箱满 → 发送方毫不知情,活链路僵死时
  /// 消息静默丢。UI 可订阅提示。
  Stream<String> get errors => _errors.stream;

  /// 发送配对应答(受邀方把 answer 引导包推回给邀请方,密文)。
  ///
  /// 加密用【offer 原始令牌】而非入账后的轮换令牌:邀请方此时还没把
  /// 受邀方入账,只能靠邀请令牌解密(fallback 路径)。
  Future<void> sendPairAnswer(String toPeerId, String answerBlob) async {
    if (!_up) throw StateError('rendezvous not connected');
    final offerToken = fallbackTokenProvider?.call();
    final codec = offerToken != null
        ? SecureCodec(offerToken)
        : _codecFor(toPeerId);
    if (codec == null) throw StateError('unknown peer $toPeerId');
    final aad = _aad(identity.deviceId, toPeerId);
    final packed = await codec.encrypt(
        utf8.encode(jsonEncode({'kind': 'pair_answer', 'blob': answerBlob})),
        aad: aad);
    _send({'type': 'signal', 'to': toPeerId, 'data': base64Encode(packed)});
  }

  /// 一次性连接回传配对应答(受邀方未配置服务器时,
  /// 临时连到邀请方所用的服务器完成推回)。
  /// [offerToken] 扫码得到的邀请令牌:邀请方尚未入账受邀方,
  /// 只能用它加密(轮换令牌解不开)。
  static Future<void> deliverPairAnswerOnce({
    required Identity identity,
    required Store store,
    required String rendezvousUrl,
    required String toPeerId,
    required String answerBlob,
    String? offerToken,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final rc =
        RendezvousClient(identity: identity, store: store, url: rendezvousUrl);
    if (offerToken != null) {
      rc.fallbackTokenProvider = () => offerToken;
    }
    try {
      rc.start();
      await rc.connectionState.firstWhere((up) => up).timeout(timeout);
      await rc.sendPairAnswer(toPeerId, answerBlob);
      // 给服务器转发留出窗口再关闭。
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      await rc.dispose();
    }
  }

  bool _up = false;
  bool get connected => _up;

  // ------------------------------------------------------------ 生命周期

  void start() {
    _stopping = false;
    _backoff = const Duration(seconds: 1); // 重启复位退避
    unawaited(_connect());
  }

  Future<void> stop() async {
    _stopping = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _markDown();
  }

  void _markDown() {
    _mailPollTimer?.cancel();
    _mailPollTimer = null;
    if (_up) {
      _up = false;
      _connected.add(false);
    }
  }

  Future<void> _connect() async {
    if (_stopping) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
      );
      // 等服务器挑战帧驱动认证(见 _onMessage)。
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onClosed() {
    _channel = null;
    _sub = null;
    _markDown();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopping || (_reconnectTimer?.isActive ?? false)) return;
    // ±50% 抖动:公共服务器重启时全体客户端不会齐连(thundering herd)。
    final jitterMs = _backoff.inMilliseconds +
        (Random().nextInt(_backoff.inMilliseconds + 1) -
                _backoff.inMilliseconds ~/ 2);
    _reconnectTimer = Timer(Duration(milliseconds: jitterMs), () {
      _backoff = _backoff * 2 > const Duration(seconds: 30)
          ? const Duration(seconds: 30)
          : _backoff * 2;
      unawaited(_connect());
    });
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (_) {}
  }

  // ------------------------------------------------------------ 消息处理

  Future<void> _onMessage(dynamic raw) async {
    if (raw is! String) return;
    Map<String, dynamic> f;
    try {
      f = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (f['type']) {
      case 'challenge':
        await _answerChallenge(f['nonce'] as String? ?? '');
      case 'hello_ok':
        _up = true;
        _backoff = const Duration(seconds: 1);
        _connected.add(true);
        subscribePeers();
        fetchMailbox();
        _startMailPolling();
      case 'presence':
        for (final raw in (f['online'] as List? ?? const [])) {
          String id;
          String? endpoint;
          if (raw is String) {
            id = raw; // 旧格式(纯 id 字符串)
            endpoint = null;
          } else {
            final item = raw as Map<String, dynamic>;
            id = item['id'] as String? ?? '';
            final ep = item['endpoint'] as String?;
            endpoint = (ep == null || ep.isEmpty) ? null : ep;
          }
          if (id.isEmpty) continue;
          _peerOnline.add(id);
          _peerOnlineEx.add(RendezvousPeerOnline(id: id, endpoint: endpoint));
        }
        for (final id in (f['offline'] as List? ?? const []).cast<String>()) {
          _peerOffline.add(id);
        }
      case 'peer_online':
        final id = f['id'] as String? ?? '';
        final ep = f['endpoint'] as String?;
        if (id.isEmpty) break;
        _peerOnline.add(id);
        _peerOnlineEx.add(RendezvousPeerOnline(
            id: id,
            endpoint: (ep == null || ep.isEmpty) ? null : ep));
      case 'peer_offline':
        _peerOffline.add(f['id'] as String? ?? '');
      case 'signal':
        await _handleSignal(f);
      case 'mailbox':
        await _handleMailbox(f);
      case 'error':
        final msg = f['message'] as String? ?? '';
        if (msg.isNotEmpty) _errors.add(msg);
        break;
    }
  }

  /// 用身份证书私钥对挑战签名,完成认证。
  /// 摘要做域分隔 + 长度前缀(与服务器 authDigest 一致,签名协议卫生)。
  Future<void> _answerChallenge(String nonce) async {
    final deviceId = identity.deviceId;
    final fingerprint = identity.fingerprint;
    String lenPrefixed(String s) => '${s.length}:$s';
    final material = 'littlelaw-hello-v1|'
        '${lenPrefixed(deviceId)}'
        '${lenPrefixed(fingerprint)}'
        '${lenPrefixed(nonce)}';
    final digest = sha256.convert(utf8.encode(material)).bytes;
    final sig = _ecSign(digest);
    _send({
      'type': 'hello',
      'deviceId': deviceId,
      'fingerprint': fingerprint,
      'cert': identity.certPem,
      'sig': sig,
      if (endpoint != null && endpoint!.isNotEmpty) 'endpoint': endpoint,
    });
  }

  String _ecSign(List<int> digest32) {
    final priv = CryptoUtils.ecPrivateKeyFromPem(identity.keyPem);
    // ECDSA 需要显式随机源(pointycastle 4.x 无默认注册)。
    final rng = Random.secure();
    final seed = List<int>.generate(32, (_) => rng.nextInt(256));
    final secureRandom = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(seed)));
    final signer = ECDSASigner();
    signer.init(
        true,
        ParametersWithRandom(
            PrivateKeyParameter<ECPrivateKey>(priv), secureRandom));
    final sig = signer.generateSignature(Uint8List.fromList(digest32))
        as ECSignature;
    final r = _pad32(sig.r);
    final s = _pad32(sig.s);
    final out = StringBuffer();
    for (final b in r) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    for (final b in s) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  List<int> _pad32(BigInt v) {
    final bytes = v.toRadixString(16).padLeft(64, '0');
    return [
      for (var i = 0; i < 64; i += 2)
        int.parse(bytes.substring(i, i + 2), radix: 16),
    ];
  }

  Future<void> _handleSignal(Map<String, dynamic> f) async {
    final from = f['from'] as String? ?? '';
    final data = f['data'] as String? ?? '';
    if (from.isEmpty || data.isEmpty) return;
    // 反射防护:声称来自自己的信令直接丢弃。
    if (from == identity.deviceId) return;

    // 候选密钥:已配对令牌 + 进行中的邀请令牌(应对令牌轮换/未入账来源)。
    final codecs = <SecureCodec>[
      if (_codecFor(from) != null) _codecFor(from)!,
      if (fallbackTokenProvider?.call() != null)
        SecureCodec(fallbackTokenProvider!()!),
    ];
    if (codecs.isEmpty) return;

    final packed = base64Decode(data);
    final aad = _aad(from, identity.deviceId);
    for (final codec in codecs) {
      try {
        final plain = await codec.decrypt(packed, aad: aad);
        final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        if (payload['kind'] == 'pair_answer') {
          final blob = payload['blob'] as String? ?? '';
          if (blob.isNotEmpty) _pairAnswers.add(blob);
          return;
        }
        _signals.add(RendezvousSignal(fromPeerId: from, payload: payload));
        return;
      } catch (_) {
        continue; // 换下一个候选密钥
      }
    }
    // 全部解密失败(伪造/损坏),丢弃
  }

  Future<void> _handleMailbox(Map<String, dynamic> f) async {
    final items = (f['items'] as List? ?? const []);
    final ackIds = <int>[];
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      final from = item['from'] as String? ?? '';
      final data = item['data'] as String? ?? '';
      final id = (item['id'] as num?)?.toInt() ?? 0;
      if (from == identity.deviceId) {
        ackIds.add(id); // 反射/伪造
        continue;
      }
      final aad = _aad(from, identity.deviceId);
      var handled = false;
      // 候选密钥:已配对令牌 + fallback 邀请令牌(旧版邮箱没有 fallback,
      // 令牌轮换/恢复场景下的合法信封会被永久删除——服务器已删无重试)。
      final codecs = <SecureCodec>[
        if (_codecFor(from) != null) _codecFor(from)!,
        if (fallbackTokenProvider?.call() != null)
          SecureCodec(fallbackTokenProvider!()!),
      ];
      for (final codec in codecs) {
        try {
          final plain = await codec.decrypt(base64Decode(data), aad: aad);
          _mail.add(RendezvousMail(
            id: id,
            fromPeerId: from,
            envelopeBytes: plain,
          ));
          handled = true;
          break;
        } catch (_) {
          continue;
        }
      }
      if (handled) {
        ackIds.add(id);
      } else if (codecs.isEmpty) {
        // 未配对来源且无 fallback:丢弃并删除。
        ackIds.add(id);
      } else {
        // 有密钥但解密失败:疑似毒消息/密钥不匹配。延迟 ack 重试一次
        //(等 fallback 令牌就位);仍然失败下次轮询会再见到——为防
        // 毒消息无限循环,直接 ack 并报错。
        _errors.add('邮箱消息解密失败(来自 ${from.substring(0, 8)}…)');
        ackIds.add(id);
      }
    }
    if (ackIds.isNotEmpty) ackMailbox(ackIds);
  }

  /// E2E 上下文绑定:sender|recipient 进 AAD,密文被反射/重定向到
  /// 其他上下文时认证失败。
  List<int> _aad(String from, String to) =>
      utf8.encode('ll-rc-v1|$from|$to');

  SecureCodec? _codecFor(String peerId) {
    final peer = store.getPeer(peerId);
    if (peer == null) return null;
    return SecureCodec(peer.token);
  }

  // ------------------------------------------------------------ 公共 API

  /// 订阅全部已配对设备的在线状态(配对变化后重新调用)。
  void subscribePeers() {
    if (!_up) return;
    _send({
      'type': 'subscribe',
      'ids': [for (final p in store.allPeers()) p.deviceId],
    });
  }

  /// 发送信令(内部加密,AAD 绑定收发双方)。
  Future<void> sendSignal(String toPeerId, Map<String, dynamic> payload) async {
    if (!_up) throw StateError('rendezvous not connected');
    final codec = _codecFor(toPeerId);
    if (codec == null) throw StateError('unknown peer $toPeerId');
    final packed = await codec.encrypt(utf8.encode(jsonEncode(payload)),
        aad: _aad(identity.deviceId, toPeerId));
    _send({'type': 'signal', 'to': toPeerId, 'data': base64Encode(packed)});
  }

  /// 投递离线信封(内部加密,AAD 绑定收发双方)。
  /// 失败(未连接/未知对端)重试一次:旧版直接丢弃,邮箱满 + 链路僵死
  /// 叠加时消息会静默丢失。
  Future<void> pushMailbox(String toPeerId, List<int> envelopeBytes) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_up) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      final codec = _codecFor(toPeerId);
      if (codec == null) return;
      final packed = await codec.encrypt(envelopeBytes,
          aad: _aad(identity.deviceId, toPeerId));
      _send({
        'type': 'mailbox_push',
        'to': toPeerId,
        'data': base64Encode(packed),
      });
      return;
    }
    _errors.add('离线邮箱投递失败(目标 $toPeerId)');
  }

  /// 拉取离线信封(mail 事件逐封到达,处理后自动 ack)。
  void fetchMailbox() {
    if (!_up) return;
    _send({'type': 'mailbox_fetch'});
  }

  void ackMailbox(List<int> ids) {
    _send({'type': 'mailbox_ack', 'ids': ids});
  }

  /// 注册移动推送令牌(FCM;服务器在收到发给本设备的离线信封时
  /// 代发唤醒通知,通知只含唤醒信号不含任何内容)。
  void registerPushToken(String token, String platform) {
    if (!_up) return;
    _send({'type': 'push_register', 'token': token, 'platform': platform});
  }

  Future<void> dispose() async {
    await stop();
    await _peerOnline.close();
    await _peerOnlineEx.close();
    await _peerOffline.close();
    await _signals.close();
    await _mail.close();
    await _connected.close();
    await _pairAnswers.close();
    await _errors.close();
  }
}
