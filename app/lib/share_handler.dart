import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'chat_page.dart';
import 'globals.dart';
import 'toast.dart';

/// 系统分享面板接入(Android):
/// 其他应用"分享" → 选 LittleLaw → 弹出设备选择器 → 直达聊天。
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
    final peers = engine.peers;
    if (peers.isEmpty) {
      showToast('收到分享内容,但还没有配对设备', type: ToastType.info);
      return;
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showModalBottomSheet(
      context: ctx,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('分享到…',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final p in peers)
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: Text(p.deviceName),
                subtitle: Text(p.deviceModel.isNotEmpty
                    ? p.deviceModel
                    : p.platform),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _sendTo(engine, p, payload);
                },
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _sendTo(
      LittleLawEngine engine, Peer peer, Map<String, dynamic> payload) async {
    try {
      final type = payload['type'] as String?;
      if (type == 'text') {
        await engine.sendText(peer.deviceId, payload['text'] as String? ?? '');
      } else if (type == 'file') {
        await engine.sendFile(peer.deviceId, payload['path'] as String? ?? '');
      } else if (type == 'files') {
        for (final path
            in (payload['paths'] as List? ?? const []).cast<String>()) {
          await engine.sendFile(peer.deviceId, path);
        }
      }
      showToast('已发送到 ${peer.deviceName}', type: ToastType.success);
      // 直达聊天页。
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.popUntil((route) => route.isFirst);
        nav.push(MaterialPageRoute(
          builder: (_) => ChatPage(peer: peer, engine: engine),
        ));
      }
    } catch (e) {
      showToast('分享发送失败: $e', type: ToastType.error);
    }
  }
}
