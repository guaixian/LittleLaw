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
      try {
        await _channel.invokeMethod('shareFile', {'path': path});
      } on PlatformException catch (e) {
        showToast('分享失败: ${e.message ?? e.code}', type: ToastType.error);
      }
      return;
    }
    if (Platform.isWindows) {
      try {
        final mode = await _channel
            .invokeMethod<String>('shareFile', {'path': path});
        if (mode == 'clipboard') {
          showToast('文件已复制,可粘贴到微信/QQ/飞书或文件夹',
              type: ToastType.success);
        } else {
          showToast('分享失败', type: ToastType.error);
        }
      } on PlatformException catch (e) {
        showToast('分享失败: ${e.message ?? e.code}', type: ToastType.error);
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
        // explorer 的 /select 语法要求 "/select,<完整路径>" 是【单个】
        // 参数;拆成两个参数时 explorer 无法解析,回退打开默认位置
        // (桌面)——旧版 bug。路径统一反斜杠并先确认存在。
        final norm = path.replaceAll('/', r'\');
        final exists = File(norm).existsSync() || Directory(norm).existsSync();
        if (!exists) {
          showToast('文件不存在(可能已被清理): ${norm.split(r'\').last}',
              type: ToastType.info);
          return;
        }
        await Process.run('explorer.exe', ['/select,$norm']);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final dir = File(path).parent.path;
        await Process.run('xdg-open', [dir]);
      }
    } catch (_) {}
  }

  /// 打开数据目录:桌面在文件管理器中定位;Android 优先经系统文件应用
  /// 定位(仅外部存储目录可达),应用私有内部目录文件管理器无法访问,
  /// 回退为复制路径提示;iOS 无文件管理器概念,同样复制路径。
  static Future<void> openDataDir(String path) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openDirectory', {'path': path});
        return;
      } on PlatformException catch (_) {
        await Clipboard.setData(ClipboardData(text: path));
        showToast('应用私有目录无法直接打开,路径已复制:\n$path',
            type: ToastType.info);
        return;
      }
    }
    if (Platform.isIOS) {
      await Clipboard.setData(ClipboardData(text: path));
      showToast('路径已复制:$path', type: ToastType.info);
      return;
    }
    await revealInFolder(path);
  }

  /// 手机:用其他应用打开(系统"打开方式"选择器)。
  static Future<void> openWithOther(String path) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openFile', {'path': path});
      } on PlatformException catch (e) {
        showToast('打开失败: ${e.message ?? e.code}', type: ToastType.error);
      }
      return;
    }
    // 桌面兜底:定位文件。
    await revealInFolder(path);
  }
}
