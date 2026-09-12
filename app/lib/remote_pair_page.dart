import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'blob_widgets.dart';
import 'toast.dart';
import 'webrtc_link.dart';

/// 远程配对页(Tab 结构):
///
/// 【创建邀请】
///   - 同一局域网:超小 tap 配对码(单张稀疏码,对方一扫即连,不经 WebRTC);
///   - 跨互联网:完整 WebRTC 邀请包(分片码 / 复制 / 导出文件 / 分享)。
/// 【加入邀请】
///   - 扫一扫(支持分片码序列自动重组)/ 粘贴文本 / 导入 .llink 文件;
///   - 应答自动回传给邀请方(地址可达时),否则展示应答引导包手动回传。
class RemotePairPage extends StatefulWidget {
  const RemotePairPage({super.key, required this.rtc});
  final WebRtcLinkManager rtc;

  @override
  State<RemotePairPage> createState() => _RemotePairPageState();
}

class _RemotePairPageState extends State<RemotePairPage> {
  // ---- 创建邀请(跨网) ----
  String? _offerBlob;
  // ---- 局域网小码 ----
  String? _lanPayload;
  int _lanRemain = 0;
  Timer? _lanTimer;
  // ---- 加入邀请 ----
  String? _answerBlob;
  String _status = '';
  String? _lastError;
  final _pasteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _lanTimer?.cancel();
    _pasteCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String s) => setState(() => _status = s);

  void _reportError(String prefix, Object e) {
    setState(() => _lastError = '$prefix: $e');
    showToast('$prefix,点下方查看详情', type: ToastType.error);
  }

  // ---------------------------------------------------------- 创建邀请

  /// 跨互联网完整邀请(WebRTC offer 引导包)。
  Future<void> _createInvite() async {
    setState(() {
      _busy = true;
      _offerBlob = null;
      _lastError = null;
      _status = '正在生成邀请(收集网络候选,约 3 秒)…';
    });
    try {
      final blob = await widget.rtc.createInvite();
      setState(() {
        _offerBlob = blob;
        _status = '邀请已生成:发送给对方,等待其加入';
      });
      showToast('邀请已生成', type: ToastType.success);
    } catch (e) {
      _setStatus('创建邀请失败');
      _reportError('创建邀请失败', e);
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 局域网超小配对码(tap 载荷,单张二维码)。
  Future<void> _createLanCode() async {
    setState(() => _busy = true);
    try {
      final engine = widget.rtc.engine;
      final payload = await engine.enableTapPairing();
      setState(() {
        _lanPayload = payload;
        _lanRemain = 120;
        _status = '局域网配对码已开启(2 分钟),对方扫这一张即可';
      });
      _lanTimer?.cancel();
      _lanTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _lanRemain--);
        if (_lanRemain <= 0) {
          t.cancel();
          setState(() => _lanPayload = null);
        }
      });
    } catch (e) {
      _reportError('生成配对码失败', e);
    } finally {
      setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------- 加入邀请

  Future<void> _acceptAnswer(String text) async {
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final peer = await widget.rtc.acceptAnswer(text.trim());
      _setStatus('已与 ${peer.deviceName} 配对,链路建立中(数秒)…');
      showToast('已与 ${peer.deviceName} 配对', type: ToastType.success);
      _pasteCtrl.clear();
    } catch (e) {
      _setStatus('应答无效');
      _reportError('应答无效', e);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _joinInvite(String text) async {
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final answer = await widget.rtc.joinInvite(text.trim());
      _pasteCtrl.clear();
      if (answer.isEmpty) {
        _setStatus('已配对!应答已自动回传给邀请方,链路建立中…');
        showToast('应答已自动回传,等待链路建立', type: ToastType.success);
      } else {
        setState(() {
          _answerBlob = answer;
          _status = '对方网络不可达,请把应答引导包回传给邀请方';
        });
        showToast('请把应答回传给邀请方', type: ToastType.success);
      }
    } catch (e) {
      _setStatus('邀请无效');
      _reportError('邀请无效', e);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BlobScanPage()),
    );
    if (result == null || !mounted) return;
    _routeIncoming(result);
  }

  /// 导入 .llink 引导包文件。
  Future<void> _importFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final text = utf8.decode(await files.single.readAsBytes()).trim();
      if (text.isEmpty) {
        showToast('文件内容为空', type: ToastType.error);
        return;
      }
      _routeIncoming(text);
    } catch (e) {
      _reportError('导入文件无效', e);
    }
  }

  /// 输入内容自动路由:局域网 tap 载荷 / offer / answer。
  void _routeIncoming(String text) {
    try {
      if (text.startsWith('LLT1.')) {
        // 局域网 tap 配对码:直接完成免 PIN 配对。
        widget.rtc.engine.pairViaLanOob(text).then((r) {
          showToast(
            r.accepted
                ? '已与 ${r.peerInfo?.deviceName ?? "对方"} 完成配对'
                : '配对失败: ${r.message}',
            type: r.accepted ? ToastType.success : ToastType.error,
          );
        });
        return;
      }
      final blob = OobBlob.decode(text);
      if (blob.isOffer) {
        _joinInvite(text);
      } else {
        _acceptAnswer(text);
      }
    } catch (e) {
      _reportError('内容无效', e);
    }
  }

  // ---------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('远程连接'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '创建邀请', icon: Icon(Icons.north_east, size: 18)),
              Tab(text: '加入邀请', icon: Icon(Icons.south_west, size: 18)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _createTab(),
            _joinTab(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 创建页

  Widget _createTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 卡 1:同一局域网(小码,一扫即连)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_outlined, color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('同一局域网',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('设备都在身边/同一网络:出示这张小码,对方一扫即完成配对,无需回传。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _createLanCode,
                    icon: const Icon(Icons.qr_code_2_outlined),
                    label: const Text('生成局域网配对码'),
                  ),
                ),
                if (_lanPayload != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text('剩余 ${_lanRemain}s',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(10),
                      child: QrImageView(
                        data: _lanPayload!,
                        size: 240,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 卡 2:跨互联网(完整邀请包)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.travel_explore_outlined,
                        color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('跨互联网(WebRTC)',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('双方不在同一网络:生成完整邀请包,经聊天工具/文件/分片码传递。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _createInvite,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('创建远程邀请'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_status,
              style: TextStyle(color: scheme.primary, fontSize: 13)),
        ],
        if (_lastError != null) _errorBox(),
        if (_offerBlob != null) ...[
          const Divider(height: 28),
          BlobDisplay(title: '我的邀请(发给对方)', blob: _offerBlob!),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ 加入页

  Widget _joinTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫一扫'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _importFile,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('导入文件'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pasteCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: '或粘贴引导包文本',
            hintText: 'LLB2. / LLT1. 开头的内容',
            suffixIcon: IconButton(
              tooltip: '从剪贴板读取',
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) _pasteCtrl.text = data!.text!;
              },
              icon: const Icon(Icons.content_paste),
            ),
          ),
          onSubmitted: _busy ? null : (v) => _routeIncoming(v.trim()),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed:
              _busy ? null : () => _routeIncoming(_pasteCtrl.text.trim()),
          icon: const Icon(Icons.login),
          label: const Text('确认加入'),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_status, style: TextStyle(color: scheme.primary, fontSize: 13)),
        ],
        if (_lastError != null) _errorBox(),
        if (_answerBlob != null) ...[
          const Divider(height: 28),
          BlobDisplay(title: '我的应答(回传给邀请方)', blob: _answerBlob!),
        ],
      ],
    );
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: SelectableText(
          _lastError!,
          style: const TextStyle(fontSize: 12, color: Colors.red),
        ),
      ),
    );
  }
}
