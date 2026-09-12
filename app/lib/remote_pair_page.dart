import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'blob_widgets.dart';
import 'toast.dart';
import 'webrtc_link.dart';

/// 远程配对页:跨互联网/跨网段建立连接。
///
/// 流程(双方各自操作):
///   邀请方:创建邀请 → 把引导包(二维码/文本)发给对方 → 等待 → 粘贴应答
///   受邀方:粘贴/扫描邀请 → 生成应答引导包 → 回传给邀请方
/// 引导包经带外通道(微信/邮件/当面扫码)传递,内含证书指纹与一次性令牌。
class RemotePairPage extends StatefulWidget {
  const RemotePairPage({super.key, required this.rtc});
  final WebRtcLinkManager rtc;

  @override
  State<RemotePairPage> createState() => _RemotePairPageState();
}

class _RemotePairPageState extends State<RemotePairPage> {
  String? _offerBlob;   // 我方邀请
  String? _answerBlob;  // 我方应答
  String _status = '';
  String? _lastError;   // 最近一次错误详情(可展开查看)
  final _pasteCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String s) => setState(() => _status = s);

  void _reportError(String prefix, Object e) {
    setState(() => _lastError = '$prefix: $e');
    showToast('$prefix,点下方查看详情', type: ToastType.error);
  }

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
        _status = '邀请已生成:发送给对方(截图/复制),然后等待并粘贴对方的应答';
      });
      showToast('邀请已生成', type: ToastType.success);
    } catch (e) {
      _setStatus('创建邀请失败');
      _reportError('创建邀请失败', e);
    } finally {
      setState(() => _busy = false);
    }
  }

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
        _setStatus('已配对(局域网直连模式),对方上线后自动通讯');
        showToast('已配对', type: ToastType.success);
      } else {
        setState(() {
          _answerBlob = answer;
          _status = '应答已生成:请把它回传给邀请方(截图/复制)';
        });
        showToast('应答已生成,请回传给邀请方', type: ToastType.success);
      }
    } catch (e) {
      _setStatus('邀请无效');
      _reportError('邀请无效', e);
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 导入 .llink 引导包文件(对方通过"导出文件/分享"发来的)。
  Future<void> _importFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final f = files.single;
      final text = utf8.decode(await f.readAsBytes()).trim();
      if (text.isEmpty) {
        showToast('文件内容为空', type: ToastType.error);
        return;
      }
      final blob = OobBlob.decode(text);
      if (blob.isOffer) {
        await _joinInvite(text);
      } else {
        await _acceptAnswer(text);
      }
    } catch (e) {
      _reportError('导入文件无效', e);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BlobScanPage()),
    );
    if (result == null || !mounted) return;
    // 扫描结果自动识别:offer → 加入;answer → 应答。
    try {
      final blob = OobBlob.decode(result);
      if (blob.isOffer) {
        await _joinInvite(result);
      } else {
        await _acceptAnswer(result);
      }
    } catch (e) {
      _reportError('二维码内容无效', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('远程连接(WebRTC)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('适用场景:双方不在同一局域网'),
              subtitle: Text('引导包经任何聊天工具带外传递;连接本身点对点加密。'
                  '运营商网络(CGNAT)下打洞可能失败,届时需配置 TURN 中继。'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _createInvite,
                icon: const Icon(Icons.send),
                label: const Text('创建邀请(我是邀请方)'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫一扫'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importFile,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('导入文件'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pasteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '粘贴引导包文本(邀请或应答)',
              hintText: 'LLB1.…',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _joinInvite(_pasteCtrl.text),
                icon: const Icon(Icons.login),
                label: const Text('加入邀请'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _acceptAnswer(_pasteCtrl.text),
                icon: const Icon(Icons.check),
                label: const Text('粘贴应答'),
              ),
              IconButton(
                tooltip: '从剪贴板读取',
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _pasteCtrl.text = data!.text!;
                  }
                },
                icon: const Icon(Icons.content_paste),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status,
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            Container(
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
          ],
          if (_offerBlob != null) ...[
            const Divider(height: 32),
            BlobDisplay(title: '我的邀请(发给对方)', blob: _offerBlob!),
          ],
          if (_answerBlob != null) ...[
            const Divider(height: 32),
            BlobDisplay(title: '我的应答(回传给邀请方)', blob: _answerBlob!),
          ],
        ],
      ),
    );
  }
}
