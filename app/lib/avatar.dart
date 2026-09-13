import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

/// 头像工具:路径、显示、选图并缩放为 PNG。
class Avatars {
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
    final f = File(path);
    if (!f.existsSync()) return null;
    return FileImage(f);
  }

  /// 选一张图片并缩放(最长边 256,保持纵横比)为 PNG 字节。
  /// 用户取消返回 null。
  static Future<Uint8List?> pickResized() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final path = files.single.path;
    if (path == null) return null;
    final raw = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(raw, targetWidth: 256);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return data?.buffer.asUint8List();
  }
}
