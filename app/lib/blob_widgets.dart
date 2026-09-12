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
///  - 长内容自动切分为【分片二维码】序列(逐张扫,自动拼回);
///  - 顶部一排主操作:复制 / 导出文件 / 分享;
///  - 原始文本折叠展示。
class BlobDisplay extends StatefulWidget {
  const BlobDisplay({super.key, required this.title, required this.blob});
  final String title;
  final String blob;

  @override
  State<BlobDisplay> createState() => _BlobDisplayState();
}

class _BlobDisplayState extends State<BlobDisplay> {
  late final List<String> _frames;
  int _index = 0;
  bool _autoPlay = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 短内容单帧;长内容切分(每帧载荷 260 字符)。
    _frames = QrChunker.split(widget.blob);
    _startAutoPlay();
  }

  void _startAutoPlay() {
    if (_frames.length <= 1) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!_autoPlay || !mounted) return;
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
        // 移动端:系统分享面板,可发到微信/邮件/网盘等。
        await SharePlus.instance.share(
            ShareParams(text: widget.blob, subject: 'LittleLaw 引导包'));
      } else {
        // 桌面端:保存为 .llink 文本文件。
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
        // 主操作按钮置顶(显眼)。
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
          ],
        ),
        const SizedBox(height: 12),
        // 二维码区(分片轮播)。
        Center(
          child: Column(
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
          ),
        ),
        const SizedBox(height: 8),
        // 原始文本折叠。
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
                  // 分片帧:收集,齐套后返回。
                  if (_reassembler.add(raw)) {
                    setState(() {});
                  }
                  if (_reassembler.complete) {
                    _done = true;
                    Navigator.of(context).pop(_reassembler.payload);
                    return;
                  }
                } else if (raw.startsWith('LLB') || raw.startsWith('LLT')) {
                  // 单帧引导包/局域网载荷:直接返回。
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
