import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

/// 头像工具:路径、显示、选图并缩放为 PNG。
class Avatars {
  /// 存在性缓存:imageOf 在列表每行 build 中被反复调用,
  /// existsSync 是同步磁盘 IO,缓存结果避免 UI 卡顿。
  static final Map<String, bool> _exists = {};

  /// 头像写入/删除后调用,使存在性缓存失效。
  static void invalidate() => _exists.clear();

  /// 头像 ImageProvider(无头像返回 null,由调用方用图标兜底)。
  static ImageProvider? imageOf(LittleLawEngine engine,
      {String? peerId, String? groupId}) {
    String path;
    if (groupId != null) {
      path = engine.groupAvatarPath(groupId);
    } else if (peerId != null) {
      path = engine.peerAvatarPath(peerId);
    } else {
      path = engine.myAvatarPath();
    }
    final cached = _exists[path];
    if (cached != null) return _provider(File(path));
    final ok = File(path).existsSync();
    _exists[path] = ok;
    // 显示侧限制解码宽度,列表行只画小头像,避免整图解码。
    return ok ? _provider(File(path)) : null;
  }

  static ImageProvider _provider(File f) =>
      ResizeImage.resizeIfNeeded(128, null, FileImage(f));

  /// 选一张图片并缩放(最长边 256,保持纵横比)为 PNG 字节。
  /// 用户取消返回 null。
  static Future<Uint8List?> pickResized() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final path = files.single.path;
    if (path == null) return null;
    final raw = await File(path).readAsBytes();
    // 先取原始尺寸,按最长边 256 等比缩放(超长图高度同样受限)。
    final probe = await ui.instantiateImageCodec(raw);
    final probeFrame = await probe.getNextFrame();
    final w = probeFrame.image.width;
    final h = probeFrame.image.height;
    probeFrame.image.dispose();
    probe.dispose();
    final targetW = w >= h ? 256 : (256 * w / h).round().clamp(1, 256);
    final targetH = h > w ? 256 : (256 * h / w).round().clamp(1, 256);
    final codec = await ui.instantiateImageCodec(raw,
        targetWidth: targetW, targetHeight: targetH);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  }
}
