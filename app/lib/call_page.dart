import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call.dart';
import 'globals.dart';
import 'theme/app_theme.dart';

/// 通话页:远程画面全屏 + 本地画中画 + 控制条;
/// 来电状态显示接听/拒绝;结束自动返回。
class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.manager});

  final CallManager manager;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  StreamSubscription<CallStateChange>? _sub;
  CallState _state = CallState.outgoing;
  bool _muted = false;
  bool _speakerOn = true;
  var _seconds = 0;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _state = widget.manager.state;
    _muted = widget.manager.muted;
    _speakerOn = widget.manager.speakerOn;
    _sub = widget.manager.stateChanges.listen((s) {
      if (!mounted) return;
      setState(() => _state = s.state);
      if (s.state == CallState.active) {
        _durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
      }
      if (s.state == CallState.ended) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  String get _stateText => switch (_state) {
        CallState.outgoing => '正在呼叫…',
        CallState.incoming => '来电',
        CallState.connecting => '连接中…',
        CallState.active => _formatDuration(_seconds),
        CallState.ended => '通话结束',
        CallState.idle => '通话结束',
      };

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      return '$h:${(m % 60).toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final peer = m.peerId != null ? rtcManager?.engine.peerById(m.peerId!) : null;
    final title = peer?.deviceName ?? 'LittleLaw 通话';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 远程画面(全屏)。
          Positioned.fill(
            child: RTCVideoView(
              m.remoteRenderer,
              objectFit:
                  RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          // 本地画中画。
          if (m.isVideo)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 70,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 108,
                  height: 150,
                  child: RTCVideoView(
                    m.localRenderer,
                    mirror: true,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          // 顶部信息(带渐变遮罩,亮画面下文字仍可读)。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                themeController.skin.primary,
                            child: Icon(
                              m.isVideo ? Icons.videocam : Icons.call,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_stateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 底部控制(带渐变遮罩)。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _controls(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final m = widget.manager;
    if (_state == CallState.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: Icons.call_end,
            color: Colors.red,
            onTap: m.reject,
          ),
          _roundButton(
            icon: Icons.call,
            color: Colors.green,
            onTap: m.accept,
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundButton(
          icon: _muted ? Icons.mic_off : Icons.mic,
          active: _muted,
          onTap: () {
            m.toggleMute();
            setState(() => _muted = m.muted);
          },
        ),
        if (m.isVideo)
          _roundButton(
            icon: Icons.cameraswitch_outlined,
            onTap: () => m.switchCamera(),
          ),
        _roundButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
          active: _speakerOn,
          onTap: () {
            m.toggleSpeaker();
            setState(() => _speakerOn = m.speakerOn);
          },
        ),
        _roundButton(
          icon: Icons.call_end,
          color: Colors.red,
          onTap: m.hangUp,
        ),
      ],
    );
  }

  Widget _roundButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    bool active = false,
  }) {
    final skin = themeController.skin;
    // 未激活底色加深 + 细边框,保证亮视频画面上按钮仍可见。
    final bg = color ??
        (active
            ? skin.primary
            : Colors.black.withValues(alpha: 0.45));
    return Material(
      color: bg,
      shape: CircleBorder(
        side: active || color != null
            ? BorderSide.none
            : BorderSide(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
