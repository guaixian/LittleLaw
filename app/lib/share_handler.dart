import 'dart:async';

import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'forward_picker.dart';
import 'toast.dart';

/// 系统分享面板接入(Android):
/// 其他应用"分享" → 选 LittleLaw → 弹出转发选择器(1:1 + 群)。
class ShareHandler {
  ShareHandler._();
  static const _channel = MethodChannel('dev.littlelaw/share');

  /// 接线(HomeShell 启动时调用一次)。
  static void attach(LittleLawEngine engine) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare' && call.arguments is Map) {
        _dispatch(engine, Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    // 冷启动分享(应用被杀状态收到分享)。
    Future.microtask(() async {
      try {
        final initial =
            await _channel.invokeMethod<Map>('getInitialShare');
        if (initial != null) {
          _dispatch(engine, Map<String, dynamic>.from(initial));
        }
      } catch (_) {}
    });
  }

  static void _dispatch(LittleLawEngine engine, Map<String, dynamic> payload) {
    if (engine.peers.isEmpty && engine.groups.isEmpty) {
      showToast('收到分享内容,但还没有配对设备', type: ToastType.info);
      return;
    }
    final type = payload['type'] as String?;
    if (type == 'text') {
      showForwardPicker(engine, text: payload['text'] as String? ?? '');
    } else if (type == 'file') {
      showForwardPicker(engine,
          filePath: payload['path'] as String? ?? '');
    } else if (type == 'files') {
      final paths =
          (payload['paths'] as List? ?? const []).cast<String>();
      if (paths.isEmpty) return;
      showForwardPicker(engine, filePaths: paths);
    }
  }
}
