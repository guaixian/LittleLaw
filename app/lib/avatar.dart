import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:littlelaw_core/littlelaw_core.dart';

/// 头像工具:路径、显示、选图并缩放为 PNG。
class Avatars {
  /// 存在性缓存:imageOf 在列表每行 build 中被反复调用,
  /// existsSync 是同步磁盘 IO,缓存结果避免 UI 卡顿。
  static final Map<String, bool> _exists = {};

  /// 近期提供过 ImageProvider 的路径集合(invalidate 时逐出 ImageCache)。
  static final _evictPaths = <String>{};

  /// 头像写入/删除后调用:存在性缓存失效 + Flutter 全局 ImageCache 逐出。
  ///
  /// 头像文件是原地覆盖写(路径不变),ImageCache 按 provider 相等性
  /// 缓存解码结果——旧版只清 _exists,不清 ImageCache,新图永远命中
  /// 旧解码缓存,换头像要重启才能看到。必须逐出 ResizeImage 包装后的
  /// 键(只 evict FileImage 无效,进缓存的是 ResizeImage)。
  static void invalidate() {
    _exists.clear();
    final cache = painting.PaintingBinding.instance.imageCache;
    for (final p in _evictPaths) {
      cache.evict(ResizeImage.resizeIfNeeded(128, null, FileImage(File(p))));
    }
    _evictPaths.clear();
  }

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
    if (cached != null) {
      if (cached) {
        _evictPaths.add(path);
        return _provider(File(path));
      }
      return null;
    }
    final ok = File(path).existsSync();
    _exists[path] = ok;
    // 显示侧限制解码宽度,列表行只画小头像,避免整图解码。
    if (!ok) return null;
    _evictPaths.add(path);
    return _provider(File(path));
  }

  static ImageProvider _provider(File f) =>
      ResizeImage.resizeIfNeeded(128, null, FileImage(f));

  /// 压缩头像为 ≤96KB 的 PNG(逐步降分辨率)。设置头像时生成【同步档】,
  /// 原图保留本地显示——压缩只发生在设置时,互传时直接读档。
  static Future<Uint8List?> encodeCapped(Uint8List raw) async {
    const cap = 96 * 1024;
    var longest = 256;
    final buf = await ui.ImmutableBuffer.fromUint8List(raw);
    final desc = await ui.ImageDescriptor.encoded(buf);
    final w = desc.width;
    final h = desc.height;
    while (true) {
      final tw =
          w >= h ? longest : (longest * w / h).round().clamp(1, longest);
      final th =
          h > w ? longest : (longest * h / w).round().clamp(1, longest);
      final codec =
          await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
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

  /// 选图 → 方形裁剪(拖动/缩放,圆形预览)→ 返回 512×512 原图 PNG。
  /// 同步档(≤96KB)由调用方经 [encodeCapped] 另行生成——原图保留本地显示。
  /// 用户在裁剪页取消返回 null。
  static Future<Uint8List?> pickAndCropped(BuildContext context) async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final path = files.single.path;
    if (path == null) return null;
    final raw = await File(path).readAsBytes();
    if (!context.mounted) return null;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => AvatarCropPage(rawBytes: raw)),
    );
    return cropped;
  }

  /// 启动维护:确保同步档 me.sync.png 存在且与原图匹配
  /// (缺失/比原图旧/仍超 96KB 时重新生成)。
  /// 旧版本把原图直接压成 ≤96KB 覆盖 me.png(原图丢失);双档模型下
  /// 原图不动,只重生成同步档。
  static Future<void> ensureMyAvatarSendable(LittleLawEngine engine) async {
    try {
      final orig = File(engine.myAvatarPath());
      if (!orig.existsSync()) return;
      final sync = File(engine.myAvatarSyncPath());
      final stale = !sync.existsSync() ||
          sync.lengthSync() > 96 * 1024 ||
          sync.lastModifiedSync().isBefore(orig.lastModifiedSync());
      if (!stale) return;
      // 旧单档迁移:me.png 本身 ≤96KB 且无 sync 档 → 直接当同步档用。
      if (!sync.existsSync() && orig.lengthSync() <= 96 * 1024) {
        await sync.writeAsBytes(orig.readAsBytesSync(), flush: true);
        return;
      }
      final bytes = await encodeCapped(orig.readAsBytesSync());
      if (bytes == null) return;
      await sync.writeAsBytes(bytes, flush: true);
      invalidate();
      engine.sync.broadcastProfile();
    } catch (_) {}
  }
}

/// 头像裁剪页:InteractiveViewer 拖动/双指缩放,圆形遮罩所见即所得,
/// 确认后按当前变换渲染 512×512 PNG(再走 ≤96KB 压缩)。
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.rawBytes});
  final Uint8List rawBytes;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _controller = TransformationController();
  ui.Image? _image;
  bool _encoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final buf = await ui.ImmutableBuffer.fromUint8List(widget.rawBytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final codec = await desc.instantiateCodec();
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
      codec.dispose();
    } catch (_) {
      if (mounted) setState(() => _error = '图片解码失败');
    }
  }

  Future<void> _confirm() async {
    final img = _image;
    if (img == null || _encoding) return;
    setState(() => _encoding = true);
    // 渲染用的 Paint(FilterQuality.medium 缩放平滑)。
    final paintPaint = Paint()..filterQuality = FilterQuality.medium;
    try {
      // 渲染尺寸(方形视口逻辑边长,取屏幕短边)。
      final size = MediaQuery.sizeOf(context);
      final s = (size.shortestSide - 48).clamp(220.0, 480.0);
      // contain 适配:图像放进 s×s 视口的初始变换。
      final s0 = math.min(s / img.width, s / img.height);
      final tx = (s - img.width * s0) / 2;
      final ty = (s - img.height * s0) / 2;
      final m = _controller.value;

      const out = 512;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // 圆形裁剪区(输出坐标)。
      canvas.clipPath(Path()
        ..addOval(Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble())));
      // 变换链(绘制调用侧右乘):输出 ← 视口 ← 手势 ← contain 适配。
      canvas.scale(out / s);
      canvas.transform(m.storage);
      canvas.translate(tx, ty);
      canvas.scale(s0);
      canvas.drawImage(img, Offset.zero, paintPaint);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(out, out);
      final data =
          await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      final png = data?.buffer.asUint8List();
      if (png == null) throw StateError('encode failed');
      // 返回 512×512 原图;同步档(≤96KB)由调用方生成,原图不再被压缩覆盖。
      if (!mounted) return;
      Navigator.of(context).pop(png);
    } catch (_) {
      if (mounted) {
        setState(() {
          _encoding = false;
          _error = '裁剪失败,请重试';
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final viewport = (size.shortestSide - 48).clamp(220.0, 480.0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('裁剪头像'),
        actions: [
          TextButton(
            onPressed: _encoding ? null : _confirm,
            child: _encoding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('确定'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            ClipOval(
              child: SizedBox(
                width: viewport,
                height: viewport,
                child: _image == null
                    ? const Center(child: CircularProgressIndicator())
                    : InteractiveViewer(
                        transformationController: _controller,
                        minScale: 1,
                        maxScale: 5,
                        boundaryMargin: const EdgeInsets.all(200),
                        child: SizedBox(
                          width: viewport,
                          height: viewport,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Image.memory(widget.rawBytes),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text('拖动调整位置,双指缩放',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
