import 'dart:io';

import 'package:flutter/services.dart';

import 'toast.dart';

/// 对外分享(微信 / QQ / 飞书等):
///  - Android:拉起系统分享面板(ACTION_SEND + FileProvider);
///  - Windows:文件/文本入剪贴板(桌面版微信/QQ/飞书均支持直接粘贴);
///  - 其他平台:文本走剪贴板,文件提示不支持。
class ShareOut {
  static const _channel = MethodChannel('dev.littlelaw/share');

  static Future<void> shareText(String text) async {
    if (text.isEmpty) return;
    if (Platform.isAndroid) {
      try {
        await _channel
            .invokeMethod('shareText', {'text': text});
        return;
      } catch (_) {
        // 落回剪贴板。
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
    showToast('已复制,可粘贴到微信/QQ/飞书', type: ToastType.success);
  }

  static Future<void> shareFile(String path) async {
    if (path.isEmpty) return;
    if (Platform.isAndroid) {
      await _channel.invokeMethod('shareFile', {'path': path});
      return;
    }
    if (Platform.isWindows) {
      final mode = await _channel
          .invokeMethod<String>('shareFile', {'path': path});
      if (mode == 'clipboard') {
        showToast('文件已复制,可粘贴到微信/QQ/飞书或文件夹',
            type: ToastType.success);
      } else {
        showToast('分享失败', type: ToastType.error);
      }
      return;
    }
    showToast('该平台暂不支持分享文件到其他应用', type: ToastType.info);
  }

  /// 读剪贴板图片(Windows 截图/复制图片后粘贴发送用)。
  /// 返回 PNG 临时文件路径;无图片返回 null。
  static Future<String?> clipboardImagePath() async {
    if (!Platform.isWindows) return null;
    try {
      return await _channel.invokeMethod<String>('readClipboardImage');
    } catch (_) {
      return null;
    }
  }
}
