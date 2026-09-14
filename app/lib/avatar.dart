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

  /// 解码原始字节并缩放为 PNG,逐步降分辨率直到 ≤96KB(信封上限,
  /// 超过引擎会拒发头像)。返回 null 表示无法编码。
  static Future<Uint8List?> _encodeCapped(Uint8List raw) async {
    const cap = 96 * 1024;
    var longest = 256;
    while (true) {
      final probe = await ui.instantiateImageCodec(raw);
      final pf = await probe.getNextFrame();
      final w = pf.image.width;
      final h = pf.image.height;
      pf.image.dispose();
      probe.dispose();
      final tw =
          w >= h ? longest : (longest * w / h).round().clamp(1, longest);
      final th =
          h > w ? longest : (longest * h / w).round().clamp(1, longest);
      final codec = await ui.instantiateImageCodec(raw,
          targetWidth: tw, targetHeight: th);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) return null;
      if (bytes.length <= cap || longest <= 64) return bytes;
      longest = longest * 3 ~/ 4; // PNG 仍超限:缩小一档重编
    }
  }

  /// 选一张图片并缩放为 PNG 字节(≤96KB)。用户取消返回 null。
  static Future<Uint8List?> pickResized() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final path = files.single.path;
    if (path == null) return null;
    final raw = await File(path).readAsBytes();
    return _encodeCapped(raw);
  }

  /// 旧版本选的头像可能超过 96KB(引擎拒发,对端永远收不到)。
  /// 启动时检查一次:超限则原地降分辨率重存,并触发广播。
  static Future<void> ensureMyAvatarSendable(LittleLawEngine engine) async {
    try {
      final f = File(engine.myAvatarPath());
      if (!f.existsSync() || f.lengthSync() <= 96 * 1024) return;
      final bytes = await _encodeCapped(f.readAsBytesSync());
      if (bytes == null) return;
      await f.writeAsBytes(bytes, flush: true);
      invalidate();
      await engine.setMyAvatar(bytes);
    } catch (_) {}
  }
}
