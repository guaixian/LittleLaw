import 'dart:async';

import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'chat_page.dart';
import 'i18n.dart';
import 'toast.dart';

/// 全库消息搜索:文本 + 文件名,跨全部会话,点击跳转会话。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.engine});
  final LittleLawEngine engine;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<Message> _results = const [];

  /// 击键防抖(300ms):旧版每击键同步全库 LIKE 查询,大库上 UI 线程卡顿。
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  void _run() {
    if (!mounted) return;
    setState(() {
      _results = widget.engine.searchMessages(_controller.text);
    });
  }

  /// 会话显示名:群名或对方设备名。
  (String, IconData, bool) _convInfo(Message m) {
    final engine = widget.engine;
    if (m.convId.startsWith('g:')) {
      final g = engine.groupById(m.convId.substring(2));
      return (g?.name ?? '已删除的群', Icons.groups_outlined, true);
    }
    // 1:1 convId = 'idA:idB'(排序拼接),取不是我的那段。
    final parts = m.convId.split(':');
    final other = parts.first == engine.identity.deviceId && parts.length > 1
        ? parts.last
        : parts.first;
    final peer = engine.peerById(other);
    final isMobile =
        peer?.platform == 'android' || peer?.platform == 'ios';
    return (
      peer?.deviceName ?? '未知设备',
      isMobile ? Icons.smartphone : Icons.computer_outlined,
      false
    );
  }

  void _open(Message m) {
    final engine = widget.engine;
    if (m.convId.startsWith('g:')) {
      final group = engine.groupById(m.convId.substring(2));
      if (group != null && engine.peers.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatPage(
              peer: engine.peers.first, engine: engine, group: group),
        ));
      } else {
        showToast('该群已解散,无法打开', type: ToastType.info);
      }
      return;
    }
    final parts = m.convId.split(':');
    final other = parts.first == engine.identity.deviceId && parts.length > 1
        ? parts.last
        : parts.first;
    final peer = engine.peerById(other);
    if (peer != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatPage(peer: peer, engine: engine),
      ));
    } else {
      showToast('对方已解除配对,无法打开', type: ToastType.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: L10n.t('search.hint'),
            border: InputBorder.none,
          ),
          onSubmitted: (_) {
            _debounce?.cancel();
            _run();
          },
          onChanged: (_) => _onChanged(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _run),
        ],
      ),
      body: _results.isEmpty
          ? Center(
              child: Text(
                _controller.text.isEmpty ? L10n.t('search.empty') : L10n.t('search.noMatch'),
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final m = _results[i];
                final (name, icon, _) = _convInfo(m);
                final isMine = m.senderId == widget.engine.identity.deviceId;
                final snippet = switch (m.kind) {
                  Message.kindImage => '[图片] ${m.text}',
                  Message.kindVideo => '[视频] ${m.text}',
                  Message.kindFile => '[文件] ${m.fileName ?? ''}',
                  Message.kindVoice => '[语音] ${m.durationMs / 1000}s',
                  _ => m.text,
                };
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(icon,
                        size: 20, color: scheme.onSecondaryContainer),
                  ),
                  title: Text(
                    snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                      isMine ? '我 → $name' : '$name → 我',
                      style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    _timeText(m.createdAtMs),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  onTap: () => _open(m),
                );
              },
            ),
    );
  }

  static String _timeText(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay
        ? '${two(t.hour)}:${two(t.minute)}'
        : '${t.month}/${t.day}';
  }
}
