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

  /// 批量分享文件:Windows 一次写入剪贴板(CF_HDROP 多文件),
  /// 可直接粘贴到微信/文件夹;Android 逐个拉起分享面板。
  static Future<void> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    if (paths.length == 1) return shareFile(paths.first);
    if (Platform.isWindows) {
      try {
        final mode = await _channel
            .invokeMethod<String>('shareFiles', {'paths': paths});
        if (mode == 'clipboard') {
          showToast('已复制 ${paths.length} 个文件,可粘贴到微信/QQ/飞书或文件夹',
              type: ToastType.success);
        } else {
          showToast('分享失败', type: ToastType.error);
        }
      } catch (_) {
        showToast('分享失败', type: ToastType.error);
      }
      return;
    }
    for (final p in paths) {
      await shareFile(p);
    }
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

  /// 读剪贴板文件列表(Windows 资源管理器复制的文件,CF_HDROP)。
  static Future<List<String>> clipboardFiles() async {
    if (!Platform.isWindows) return const [];
    try {
      final list =
          await _channel.invokeMethod<List<dynamic>>('readClipboardFiles');
      return (list ?? const []).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// 桌面:在文件管理器中定位并选中该文件。
  static Future<void> revealInFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final dir = File(path).parent.path;
        await Process.run('xdg-open', [dir]);
      }
    } catch (_) {}
  }

  /// 手机:用其他应用打开(系统"打开方式"选择器)。
  static Future<void> openWithOther(String path) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('openFile', {'path': path});
      return;
    }
    // 桌面兜底:定位文件。
    await revealInFolder(path);
  }
}
