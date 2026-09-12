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
  });

  final Identity identity;
  final Store store;
  final String url; // ws://host:port/ws 或 wss://domain/ws

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Duration _backoff = const Duration(seconds: 1);
  bool _stopping = false;

  final _peerOnline = StreamController<String>.broadcast();
  final _peerOffline = StreamController<String>.broadcast();
  final _signals = StreamController<RendezvousSignal>.broadcast();
  final _mail = StreamController<RendezvousMail>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  Stream<String> get peerOnline => _peerOnline.stream;
  Stream<String> get peerOffline => _peerOffline.stream;
  Stream<RendezvousSignal> get signals => _signals.stream;
  Stream<RendezvousMail> get mail => _mail.stream;
  Stream<bool> get connectionState => _connected.stream;

  bool _up = false;
  bool get connected => _up;

  // ------------------------------------------------------------ 生命周期

  void start() {
    _stopping = false;
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
    _reconnectTimer = Timer(_backoff, () {
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
      case 'presence':
        for (final id in (f['online'] as List? ?? const []).cast<String>()) {
          _peerOnline.add(id);
        }
        for (final id in (f['offline'] as List? ?? const []).cast<String>()) {
          _peerOffline.add(id);
        }
      case 'peer_online':
        _peerOnline.add(f['id'] as String? ?? '');
      case 'peer_offline':
        _peerOffline.add(f['id'] as String? ?? '');
      case 'signal':
        await _handleSignal(f);
      case 'mailbox':
        await _handleMailbox(f);
      case 'error':
        break; // 服务器提示(如对端不在线),静默
    }
  }

  /// 用身份证书私钥对挑战签名,完成认证。
  Future<void> _answerChallenge(String nonce) async {
    final deviceId = identity.deviceId;
    final fingerprint = identity.fingerprint;
    final digest = sha256.convert(utf8.encode('$deviceId|$fingerprint|$nonce')).bytes;
    final sig = _ecSign(digest);
    _send({
      'type': 'hello',
      'deviceId': deviceId,
      'fingerprint': fingerprint,
      'cert': identity.certPem,
      'sig': sig,
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
    final codec = _codecFor(from);
    if (codec == null) return; // 未配对来源,丢弃
    try {
      final plain = await codec.decrypt(base64Decode(data));
      _signals.add(RendezvousSignal(
        fromPeerId: from,
        payload: jsonDecode(utf8.decode(plain)) as Map<String, dynamic>,
      ));
    } catch (_) {
      // 解密失败(伪造/损坏),丢弃
    }
  }

  Future<void> _handleMailbox(Map<String, dynamic> f) async {
    final items = (f['items'] as List? ?? const []);
    final ackIds = <int>[];
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      final from = item['from'] as String? ?? '';
      final data = item['data'] as String? ?? '';
      final id = (item['id'] as num?)?.toInt() ?? 0;
      final codec = _codecFor(from);
      if (codec == null) {
        ackIds.add(id); // 未配对来源:直接丢弃并删除
        continue;
      }
      try {
        final plain = await codec.decrypt(base64Decode(data));
        _mail.add(RendezvousMail(
          id: id,
          fromPeerId: from,
          envelopeBytes: plain,
        ));
        ackIds.add(id);
      } catch (_) {
        ackIds.add(id); // 解密失败也丢弃(防止毒消息反复投递)
      }
    }
    if (ackIds.isNotEmpty) ackMailbox(ackIds);
  }

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

  /// 发送信令(内部加密)。
  Future<void> sendSignal(String toPeerId, Map<String, dynamic> payload) async {
    if (!_up) throw StateError('rendezvous not connected');
    final codec = _codecFor(toPeerId);
    if (codec == null) throw StateError('unknown peer $toPeerId');
    final packed = await codec.encrypt(utf8.encode(jsonEncode(payload)));
    _send({'type': 'signal', 'to': toPeerId, 'data': base64Encode(packed)});
  }

  /// 投递离线信封(内部加密)。
  Future<void> pushMailbox(String toPeerId, List<int> envelopeBytes) async {
    if (!_up) return;
    final codec = _codecFor(toPeerId);
    if (codec == null) return;
    final packed = await codec.encrypt(envelopeBytes);
    _send({
      'type': 'mailbox_push',
      'to': toPeerId,
      'data': base64Encode(packed),
    });
  }

  /// 拉取离线信封(mail 事件逐封到达,处理后自动 ack)。
  void fetchMailbox() {
    if (!_up) return;
    _send({'type': 'mailbox_fetch'});
  }

  void ackMailbox(List<int> ids) {
    _send({'type': 'mailbox_ack', 'ids': ids});
  }

  Future<void> dispose() async {
    await stop();
    await _peerOnline.close();
    await _peerOffline.close();
    await _signals.close();
    await _mail.close();
    await _connected.close();
  }
}
