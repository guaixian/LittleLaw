import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

/// WebRTC 链路管理:跨互联网/跨网段的 P2P 通道。
///
/// 角色:RTCPeerConnection + 可靠有序 DataChannel 承载与 gRPC 相同的
/// Envelope 流;建连信令(SDP/ICE)经 OOB 引导包(二维码/粘贴)带外交换;
/// 通道打开后先过 LinkAuth 鉴权,再挂载进 SyncEngine 统一同步。
class WebRtcLinkManager {
  WebRtcLinkManager({required this.engine, List<String>? iceServers})
      : iceServers = iceServers ?? defaultIceServers;

  /// 默认 STUN 列表(国内外混合,全部无状态"照妖镜"服务)。
  /// 可在设置页自行增删;打洞失败时配置 TURN 中继兜底。
  static const defaultIceServers = [
    'stun:stun.l.google.com:19302',
    'stun:stun.miwifi.com:3478',
    'stun:stun.chat.bilibili.com:3478',
  ];

  final LittleLawEngine engine;
  List<String> iceServers;

  static const _gatherWindow = Duration(seconds: 3);
  static const _authTimeout = Duration(seconds: 10);

  _PendingOffer? _pendingOffer;
  final _links = <String, _ActiveLink>{};
  final _linkEvents = StreamController<WebRtcLinkEvent>.broadcast();

  /// 链路状态事件(UI 提示用)。
  Stream<WebRtcLinkEvent> get linkEvents => _linkEvents.stream;

  bool isLinked(String peerId) => _links.containsKey(peerId);

  // ------------------------------------------------------------ 邀请方

  /// 创建远程邀请:建立 PeerConnection + DataChannel,收集 ICE 候选,
  /// 返回可展示(二维码)/可粘贴的 offer 引导包字符串。
  /// 每个阶段独立报错并带超时,失败原因精确定位。
  Future<String> createInvite() async {
    await closePendingOffer();
    final token = engine.beginRemoteOffer();

    RTCPeerConnection pc;
    try {
      pc = await createPeerConnection(_rtcConfig())
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw StateError('WebRTC 初始化失败(libwebrtc): $e');
    }

    RTCDataChannel dc;
    try {
      dc = await pc
          .createDataChannel('littlelaw', RTCDataChannelInit()..ordered = true)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      await pc.close();
      throw StateError('创建数据通道失败: $e');
    }

    final candidates = <String>[];
    final gathered = Completer<void>();
    pc.onIceCandidate = (c) {
      if (c.candidate != null && c.candidate!.isNotEmpty) {
        candidates.add(jsonEncode(c.toMap()));
      }
    };
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };

    try {
      final offer = await pc.createOffer().timeout(const Duration(seconds: 10));
      await pc
          .setLocalDescription(offer)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      await pc.close();
      throw StateError('生成/设置 offer 失败: $e');
    }

    // ICE 候选收集窗口(超时照常继续,可能只有 host 候选)。
    await gathered.future.timeout(_gatherWindow, onTimeout: () {});

    RTCSessionDescription? local;
    try {
      local = await pc.getLocalDescription().timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (local?.sdp == null || local!.sdp!.isEmpty) {
      await pc.close();
      throw StateError('未生成本地描述(网络候选收集失败,检查网络/防火墙)');
    }

    _pendingOffer = _PendingOffer(pc: pc, dc: dc, token: token);
    return OobBlob(
      type: OobBlob.typeOffer,
      deviceId: engine.identity.deviceId,
      deviceName: engine.identity.deviceName,
      platform: Identity.platformName(),
      fingerprint: engine.identity.fingerprint,
      token: token,
      deviceModel: engine.identity.deviceModel,
      sdp: local.sdp,
      candidates: _pickCandidates(candidates),
    ).encode();
  }

  /// 粘贴/扫描对方的 answer 引导包,完成配对并建立链路。
  Future<Peer> acceptAnswer(String blobText) async {
    final blob = OobBlob.decode(blobText);
    final pending = _pendingOffer;
    if (pending == null) {
      throw StateError('没有进行中的邀请,请先"创建邀请"');
    }
    // 入账(校验令牌回显,失败抛异常)。
    final peer = engine.acceptRemoteAnswer(blob);

    if (blob.hasRtc) {
      await pending.pc.setRemoteDescription(
          RTCSessionDescription(blob.sdp, 'answer'));
      for (final c in blob.candidates) {
        await pending.pc.addCandidate(_candidateFromJson(c));
      }
      _armChannel(pending.dc, pending.pc, peer);
      _pendingOffer = null;
    } else {
      // 对方无 WebRTC 数据(近场扫码直连局域网):尝试 gRPC 直连。
      _tryDirectGrpc(peer, blob);
      _pendingOffer = null;
    }
    return peer;
  }

  /// 放弃进行中的邀请。
  Future<void> closePendingOffer() async {
    final p = _pendingOffer;
    _pendingOffer = null;
    if (p != null) {
      await p.dc.close();
      await p.pc.close();
    }
    engine.cancelRemoteOffer();
  }

  // ------------------------------------------------------------ 受邀方

  /// 加入对方的邀请:应用 offer 引导包(入账),生成 answer 引导包字符串
  /// (需回传给邀请方)。
  Future<String> joinInvite(String blobText) async {
    final blob = OobBlob.decode(blobText);
    if (!blob.isOffer) throw ArgumentError('这是应答包,请使用"粘贴应答"');
    final peer = engine.acceptRemoteOffer(blob); // 入账(带外信任锚)

    if (!blob.hasRtc) {
      // 对端纯局域网引导包:直连其 gRPC 地址候选,无 answer 需回传。
      _tryDirectGrpc(peer, blob);
      return '';
    }

    RTCPeerConnection pc;
    try {
      pc = await createPeerConnection(_rtcConfig())
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw StateError('WebRTC 初始化失败(libwebrtc): $e');
    }
    final candidates = <String>[];
    final gathered = Completer<void>();
    pc.onIceCandidate = (c) {
      if (c.candidate != null && c.candidate!.isNotEmpty) {
        candidates.add(jsonEncode(c.toMap()));
      }
    };
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    // 受邀方的 DataChannel 由对端创建,经回调到达。
    pc.onDataChannel = (dc) => _armChannel(dc, pc, peer);

    try {
      await pc
          .setRemoteDescription(RTCSessionDescription(blob.sdp, 'offer'))
          .timeout(const Duration(seconds: 10));
      for (final c in blob.candidates) {
        await pc.addCandidate(_candidateFromJson(c));
      }
      final answer = await pc.createAnswer().timeout(const Duration(seconds: 10));
      await pc
          .setLocalDescription(answer)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      await pc.close();
      throw StateError('生成应答失败: $e');
    }
    await gathered.future.timeout(_gatherWindow, onTimeout: () {});

    final local = await pc.getLocalDescription().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null);
    return OobBlob(
      type: OobBlob.typeAnswer,
      deviceId: engine.identity.deviceId,
      deviceName: engine.identity.deviceName,
      platform: Identity.platformName(),
      fingerprint: engine.identity.fingerprint,
      token: blob.token, // 令牌原样回显
      deviceModel: engine.identity.deviceModel,
      sdp: local?.sdp,
      candidates: _pickCandidates(candidates),
    ).encode();
  }

  /// 裁剪 ICE 候选,控制引导包体积(二维码容量有限)。
  /// 优先级:srflx(公网映射,打洞关键)> host(直连)> 其他,最多 5 条。
  List<String> _pickCandidates(List<String> all, {int max = 5}) {
    final srflx = all.where((c) => c.contains(' typ srflx')).toList();
    final host = all.where((c) => c.contains(' typ host')).toList();
    final rest = all
        .where((c) => !c.contains(' typ srflx') && !c.contains(' typ host'))
        .toList();
    final picked = <String>[
      ...srflx.take(3),
      ...host.take(2),
      ...rest.take(2),
    ];
    return picked.take(max).toList();
  }

  // ------------------------------------------------------------ 通道武装

  /// DataChannel 打开 → 互发 LinkAuth → 校验通过 → 挂载进同步引擎。
  void _armChannel(RTCDataChannel dc, RTCPeerConnection pc, Peer peer) {
    final incoming = StreamController<Envelope>();
    StreamController<Envelope>? sink;
    var authed = false;
    var opened = false;

    var tornDown = false;
    void teardown() {
      if (tornDown) return;
      tornDown = true;
      if (sink != null) {
        engine.detachExternalTransport(peer.deviceId, sink!);
        sink = null;
      }
      unawaited(incoming.close());
      unawaited(pc.close());
      _links.remove(peer.deviceId);
      _linkEvents.add(WebRtcLinkEvent(peer.deviceId, false));
    }

    dc.onMessage = (msg) {
      if (!msg.isBinary) return;
      Envelope env;
      try {
        env = Envelope.fromBuffer(msg.binary);
      } catch (_) {
        return;
      }
      if (!authed) {
        // 第一个信封必须是 LinkAuth,且身份/令牌与入账记录一致。
        if (!env.hasLinkAuth() ||
            env.linkAuth.deviceId != peer.deviceId ||
            !Auth.constantTimeEquals(env.linkAuth.token, peer.token)) {
          unawaited(dc.close());
          return;
        }
        authed = true;
        sink = engine.attachExternalTransport(peer.deviceId, incoming.stream);
        sink!.stream.listen((e) {
          dc.send(RTCDataChannelMessage.fromBinary(e.writeToBuffer()));
        });
        _links[peer.deviceId] =
            _ActiveLink(pc: pc, dc: dc, incoming: incoming);
        _linkEvents.add(WebRtcLinkEvent(peer.deviceId, true));
        return;
      }
      incoming.add(env);
    };

    dc.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen && !opened) {
        opened = true;
        // 发送我方 LinkAuth(对端验明正身的依据)。
        dc.send(RTCDataChannelMessage.fromBinary(Envelope(
          id: 'auth-${DateTime.now().microsecondsSinceEpoch}',
          linkAuth: LinkAuth(
            deviceId: engine.identity.deviceId,
            token: peer.token,
          ),
        ).writeToBuffer()));
        // 鉴权超时保护。
        Timer(_authTimeout, () {
          if (!authed) unawaited(dc.close());
        });
      } else if (state == RTCDataChannelState.RTCDataChannelClosed ||
          state == RTCDataChannelState.RTCDataChannelClosing) {
        teardown();
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        teardown();
      }
    };
  }

  /// 近场扫码直连:引导包携带局域网地址时直接走 gRPC(无需 WebRTC)。
  void _tryDirectGrpc(Peer peer, OobBlob blob) {
    for (final addr in blob.addresses) {
      final idx = addr.lastIndexOf(':');
      if (idx <= 0) continue;
      final host = addr.substring(0, idx);
      final port = int.tryParse(addr.substring(idx + 1));
      if (port == null) continue;
      engine.sync.notePeerAddress(peer, host, port);
      break; // 先用第一个候选,失败由会话重连机制兜底
    }
  }

  /// 主动断开某对端的 WebRTC 链路。
  Future<void> disconnect(String peerId) async {
    final link = _links.remove(peerId);
    if (link != null) {
      await link.dc.close();
      await link.pc.close();
      unawaited(link.incoming.close());
    }
    _linkEvents.add(WebRtcLinkEvent(peerId, false));
  }

  Map<String, dynamic> _rtcConfig() => {
        'iceServers': [
          for (final s in iceServers)
            s.startsWith('turn')
                ? {'urls': s, 'username': _turnUsername, 'credential': _turnCredential}
                : {'urls': s},
        ],
        'sdpSemantics': 'unified-plan',
      };

  // TURN 凭据(设置页配置)。
  String? _turnUsername;
  String? _turnCredential;
  void configureTurn({String? username, String? credential}) {
    _turnUsername = username;
    _turnCredential = credential;
  }

  RTCIceCandidate _candidateFromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return RTCIceCandidate(
        map['candidate'] as String?, map['sdpMid'] as String?,
        map['sdpMLineIndex'] as int?);
  }

  Future<void> dispose() async {
    await closePendingOffer();
    for (final id in _links.keys.toList()) {
      await disconnect(id);
    }
    await _linkEvents.close();
  }
}

class WebRtcLinkEvent {
  WebRtcLinkEvent(this.peerId, this.connected);
  final String peerId;
  final bool connected;
}

class _PendingOffer {
  _PendingOffer({required this.pc, required this.dc, required this.token});
  final RTCPeerConnection pc;
  final RTCDataChannel dc;
  final String token;
}

class _ActiveLink {
  _ActiveLink({required this.pc, required this.dc, required this.incoming});
  final RTCPeerConnection pc;
  final RTCDataChannel dc;
  final StreamController<Envelope> incoming;
}

void unawaited(Future<void> f) {}
