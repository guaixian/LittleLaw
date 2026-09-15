import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:uuid/uuid.dart';

import 'webrtc_link.dart';

enum CallState { idle, outgoing, incoming, connecting, active, ended }

class CallStateChange {
  CallStateChange(this.state, {this.peerId, this.video = false, this.error});
  final CallState state;
  final String? peerId;
  final bool video;
  final String? error;
}

/// 音视频通话管理:信令走已认证信封通道(LAN gRPC / WebRTC 链路通用),
/// 媒体走独立 WebRTC PeerConnection(DTLS-SRTP 端到端加密)。
class CallManager {
  CallManager({required this.engine, List<String>? iceServers})
      : iceServers = iceServers ?? WebRtcLinkManager.defaultIceServers;

  final LittleLawEngine engine;
  List<String> iceServers;

  final _stateChanges = StreamController<CallStateChange>.broadcast();
  Stream<CallStateChange> get stateChanges => _stateChanges.stream;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<EngineEvent>? _eventSub;

  String? _callId;
  String? _peerId;
  bool _video = false;
  bool _muted = false;
  bool _speakerOn = true;
  CallOffer? _pendingOffer;
  Timer? _ringTimeout;

  /// 被叫响铃期间先到的 ICE 候选缓冲(主叫 host 候选几秒内收完,
  /// 晚接电话≈全部到达;旧版 _pc == null 直接丢弃,对称 NAT 下
  /// 打洞必败)。SRD 完成后统一 flush。
  final _earlyCandidates = <RTCIceCandidate>[];

  /// 已处理过的 answer(防重复投递触发 "wrong state" 异常)。
  final _answeredCallIds = <String>{};

  CallState _state = CallState.idle;
  CallState get state => _state;
  String? get peerId => _peerId;
  bool get isVideo => _video;
  bool get muted => _muted;
  bool get speakerOn => _speakerOn;

  Map<String, dynamic> _rtcConfig() => {
        'iceServers': [for (final s in iceServers) {'urls': s}],
        'sdpSemantics': 'unified-plan',
      };

  // ------------------------------------------------------------ 生命周期

  void start() {
    _eventSub?.cancel();
    _eventSub = engine.events.listen(_onEngineEvent);
    unawaited(localRenderer.initialize());
    unawaited(remoteRenderer.initialize());
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _teardown('dispose');
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    await _stateChanges.close();
  }

  // ------------------------------------------------------------ 发起

  Future<void> startCall(String peerId, {required bool video}) async {
    if (_state != CallState.idle) return;
    _peerId = peerId;
    _video = video;
    _callId = const Uuid().v4();
    // 同步先占状态:openUserMedia 有秒级 await,双击发起会创建两个 PC
    //(第一个 PC 与摄像头/麦克风轨道永不释放),失败时 teardown 复位。
    _setState(CallState.outgoing);
    try {
      await _openUserMedia(video);
      _pc = await _createPc();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      engine.sync.sendEnvelope(peerId, Envelope(
        id: const Uuid().v4(),
        callOffer: CallOffer(callId: _callId, sdp: offer.sdp!, video: video),
      ));
      _armRingTimeout();
    } catch (e) {
      await _teardown('startCall failed: $e');
    }
  }

  // ------------------------------------------------------------ 接听/拒绝

  Future<void> accept() async {
    final offer = _pendingOffer;
    if (_state != CallState.incoming || offer == null) return;
    _ringTimeout?.cancel();
    // 同步先占状态(重入保护,同 startCall)。
    _setState(CallState.connecting);
    try {
      await _openUserMedia(_video);
      _pc = await _createPc();
      await _pc!.setRemoteDescription(
          RTCSessionDescription(offer.sdp, 'offer'));
      await _flushEarlyCandidates();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      engine.sync.sendEnvelope(_peerId!, Envelope(
        id: const Uuid().v4(),
        callAnswer: CallAnswer(
            callId: _callId!, sdp: answer.sdp!, accepted: true),
      ));
    } catch (e) {
      await _teardown('accept failed: $e');
    }
  }

  Future<void> reject() => _sendEnd('reject');

  Future<void> hangUp() => _sendEnd('hangup');

  Future<void> _sendEnd(String reason) async {
    final callId = _callId;
    final peerId = _peerId;
    if (callId != null && peerId != null) {
      engine.sync.sendEnvelope(peerId, Envelope(
        id: const Uuid().v4(),
        callEnd: CallEnd(callId: callId, reason: reason),
      ));
    }
    await _teardown(reason);
  }

  // ------------------------------------------------------------ 控制

  void toggleMute() {
    final stream = _localStream;
    if (stream == null) return;
    _muted = !_muted;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_muted;
    }
    _stateChanges.add(CallStateChange(_state, peerId: _peerId, video: _video));
  }

  Future<void> switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      await Helper.switchCamera(track);
    }
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
    _stateChanges.add(CallStateChange(_state, peerId: _peerId, video: _video));
  }

  // ------------------------------------------------------------ 信令事件

  void _onEngineEvent(EngineEvent e) {
    switch (e) {
      case CallOfferReceived(:final peerId, :final offer):
        _onOffer(peerId, offer);
      case CallAnswerReceived(:final peerId, :final answer):
        _onAnswer(peerId, answer);
      case CallCandidateReceived(:final peerId, :final candidate):
        _onCandidate(peerId, candidate);
      case CallEndReceived(:final peerId, :final end):
        if (peerId == _peerId && end.callId == _callId) {
          _teardown(end.reason);
        }
      default:
        break; // 非通话事件
    }
  }

  void _onOffer(String peerId, CallOffer offer) {
    if (_state != CallState.idle) {
      // 忙线。
      engine.sync.sendEnvelope(peerId, Envelope(
        id: const Uuid().v4(),
        callEnd: CallEnd(callId: offer.callId, reason: 'busy'),
      ));
      return;
    }
    _peerId = peerId;
    _callId = offer.callId;
    _video = offer.video;
    _pendingOffer = offer;
    _setState(CallState.incoming);
    _armRingTimeout();
  }

  Future<void> _onAnswer(String peerId, CallAnswer answer) async {
    if (peerId != _peerId || answer.callId != _callId || _pc == null) return;
    // 重复投递防护:同一 callId 的 answer 只处理一次(重复 SRD 抛
    // "wrong state" 未处理 zone 异常,状态机卡 connecting 等 45s 超时)。
    if (!_answeredCallIds.add(answer.callId)) return;
    _ringTimeout?.cancel();
    if (!answer.accepted) {
      await _teardown('reject');
      return;
    }
    try {
      await _pc!
          .setRemoteDescription(RTCSessionDescription(answer.sdp, 'answer'));
      await _flushEarlyCandidates();
      _setState(CallState.connecting);
    } catch (e) {
      await _teardown('bad answer: $e');
    }
  }

  Future<void> _onCandidate(String peerId, CallCandidate candidate) async {
    if (peerId != _peerId || candidate.callId != _callId) {
      return;
    }
    final c = RTCIceCandidate(
        candidate.candidate, candidate.sdpMid, candidate.sdpMlineIndex);
    // 响铃期间 PC 未建:缓冲等 SRD 后补(SRD 前直接 addCandidate 会抛错)。
    if (_pc == null) {
      if (_earlyCandidates.length < 64) _earlyCandidates.add(c);
      return;
    }
    try {
      await _pc!.addCandidate(c);
    } catch (_) {
      // SRD 恰好还在进行等时序错位:缓冲到下一个候选前重试一次。
      if (_earlyCandidates.length < 64) _earlyCandidates.add(c);
    }
  }

  Future<void> _flushEarlyCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final pending = List.of(_earlyCandidates);
    _earlyCandidates.clear();
    for (final c in pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ 内部

  Future<void> _openUserMedia(bool video) async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    localRenderer.srcObject = _localStream;
  }

  Future<RTCPeerConnection> _createPc() async {
    final pc = await createPeerConnection(_rtcConfig());
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      engine.sync.sendEnvelope(_peerId!, Envelope(
        id: const Uuid().v4(),
        callCandidate: CallCandidate(
          callId: _callId!,
          candidate: c.candidate!,
          sdpMid: c.sdpMid ?? '',
          sdpMlineIndex: c.sdpMLineIndex ?? 0,
        ),
      ));
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        _setState(CallState.active);
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(CallState.active);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _teardown('connection $state');
      }
    };
    return pc;
  }

  void _armRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (_state == CallState.outgoing || _state == CallState.incoming) {
        _sendEnd('timeout');
      }
    });
  }

  void _setState(CallState s) {
    _state = s;
    _stateChanges
        .add(CallStateChange(s, peerId: _peerId, video: _video));
  }

  Future<void> _teardown(String reason) async {
    _ringTimeout?.cancel();
    final wasActive = _state != CallState.idle;
    _state = CallState.ended;
    _pendingOffer = null;
    _earlyCandidates.clear();
    if (_answeredCallIds.length > 64) _answeredCallIds.clear();
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    if (wasActive) {
      _stateChanges.add(CallStateChange(CallState.ended,
          peerId: _peerId, video: _video, error: reason));
    }
    _state = CallState.idle;
    _callId = null;
    _peerId = null;
  }
}
