import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 图片全屏预览:双击缩放 + 双指捏合缩放 + 拖动平移。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.path, this.heroTag});
  final String path;
  final String? heroTag;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final _controller = TransformationController();
  var _zoomed = false;

  void _toggleZoom(Offset focalPoint) {
    setState(() {
      if (_zoomed) {
        _controller.value = Matrix4.identity();
      } else {
        _controller.value = Matrix4.identity()
          ..translateByDouble(-focalPoint.dx * 1.5, -focalPoint.dy * 1.5, 0, 1)
          ..scaleByDouble(2.5, 2.5, 2.5, 1);
      }
      _zoomed = !_zoomed;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _toggleZoom(d.localPosition),
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 0.5,
          maxScale: 6,
          child: Center(
            child: Hero(
              tag: widget.heroTag ?? widget.path,
              child: Image.file(
                File(widget.path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 80),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 视频全屏播放页(media_kit,全平台,自带控制条)。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final _player = Player();
  late final _controller = VideoController(_player);
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.open(Media(widget.path));
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('播放失败:\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              )
            : Video(
                controller: _controller,
                fill: Colors.black,
              ),
      ),
    );
  }
}
