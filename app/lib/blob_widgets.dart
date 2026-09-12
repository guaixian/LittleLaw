import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'toast.dart';

/// 引导包展示组件:
///  - 【单码模式】数据 ≤ 单张二维码容量时默认:一张完整大码(自适应放大);
///  - 【分片模式】扫不出来可一键切换,或数据超限时自动:切为小帧轮播;
///  - 顶部主操作:复制 / 导出文件 / 分享;
///  - 原始文本折叠展示。
class BlobDisplay extends StatefulWidget {
  const BlobDisplay({super.key, required this.title, required this.blob});
  final String title;
  final String blob;

  /// 单张二维码容量(字节模式 v40-L)。
  static const singleQrCapacity = 2953;

  @override
  State<BlobDisplay> createState() => _BlobDisplayState();
}

class _BlobDisplayState extends State<BlobDisplay> {
  late final List<String> _frames;
  late final bool _fitsSingle;
  late bool _singleMode;
  int _index = 0;
  bool _autoPlay = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _frames = QrChunker.split(widget.blob);
    _fitsSingle = widget.blob.length <= BlobDisplay.singleQrCapacity;
    _singleMode = _fitsSingle;
    _startAutoPlay();
  }

  void _startAutoPlay() {
    if (_frames.length <= 1) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_autoPlay || !mounted || _singleMode) return;
      setState(() => _index = (_index + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.blob));
    showToast('已复制到剪贴板', type: ToastType.success);
  }

  Future<void> _exportFile() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await SharePlus.instance.share(
            ShareParams(text: widget.blob, subject: 'LittleLaw 引导包'));
      } else {
        final path = await FilePicker.saveFile(
          dialogTitle: '导出引导包',
          fileName: 'littlelaw-invite.llink',
          bytes: Uint8List.fromList(utf8.encode(widget.blob)),
        );
        if (path != null) {
          showToast('已导出到 $path', type: ToastType.success);
        }
      }
    } catch (e) {
      showToast('导出失败: $e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final multi = _frames.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        // 主操作按钮置顶。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('复制引导包'),
            ),
            OutlinedButton.icon(
              onPressed: _exportFile,
              icon: Icon(
                  Platform.isAndroid || Platform.isIOS
                      ? Icons.ios_share_outlined
                      : Icons.save_outlined,
                  size: 18),
              label: Text(Platform.isAndroid || Platform.isIOS ? '分享' : '导出文件'),
            ),
            if (multi && _fitsSingle)
              OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _singleMode = !_singleMode),
                icon: Icon(_singleMode
                    ? Icons.grid_view_outlined
                    : Icons.crop_square_outlined, size: 18),
                label: Text(_singleMode ? '切分片码' : '切单码'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: _singleMode ? _singleQr(context) : _chunkedQr(context, multi),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('原始引导包文本', style: TextStyle(fontSize: 13)),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                widget.blob,
                maxLines: 6,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 单张完整大码:自适应取可用宽度(上限 480),保证码点像素密度可扫。
  Widget _singleQr(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = constraints.maxWidth.clamp(280.0, 480.0);
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12), // 静区
          child: QrImageView(
            data: widget.blob,
            size: size,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
            errorStateBuilder: (ctx, err) => SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '内容超出单张容量,请切换分片码',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 分片轮播小码。
  Widget _chunkedQr(BuildContext context, bool multi) {
    return Column(
      children: [
        if (multi)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('分片码 ${_index + 1}/${_frames.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _autoPlay = !_autoPlay),
                  child: Icon(
                    _autoPlay
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        GestureDetector(
          onTap: () => setState(() => _autoPlay = !_autoPlay),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: QrImageView(
              key: ValueKey(_index),
              data: _frames[_index],
              size: 260,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
              errorStateBuilder: (ctx, err) => const SizedBox(
                width: 260,
                height: 260,
                child: Center(
                  child: Text('此帧过大,请使用复制或导出方式传递',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54)),
                ),
              ),
            ),
          ),
        ),
        if (multi)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('对方逐张扫描即可,无需按顺序',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ),
      ],
    );
  }
}

/// 扫码页:支持单帧与分片序列自动重组。
class BlobScanPage extends StatefulWidget {
  const BlobScanPage({super.key});

  @override
  State<BlobScanPage> createState() => _BlobScanPageState();
}

class _BlobScanPageState extends State<BlobScanPage> {
  final _reassembler = QrReassembler();
  var _done = false;

  @override
  Widget build(BuildContext context) {
    final total = _reassembler.total;
    final received = _reassembler.received;
    return Scaffold(
      appBar: AppBar(title: const Text('扫描引导包')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_done) return;
              for (final code in capture.barcodes) {
                final raw = code.rawValue;
                if (raw == null) continue;
                if (QrChunker.isChunk(raw)) {
                  if (_reassembler.add(raw)) {
                    setState(() {});
                  }
                  if (_reassembler.complete) {
                    _done = true;
                    Navigator.of(context).pop(_reassembler.payload);
                    return;
                  }
                } else if (raw.startsWith('LLB') || raw.startsWith('LLT')) {
                  _done = true;
                  Navigator.of(context).pop(raw);
                  return;
                }
              }
            },
          ),
          if (total > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '分片码进度 $received/$total,继续扫描',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
