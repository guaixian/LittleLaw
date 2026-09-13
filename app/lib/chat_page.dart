import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'media_viewers.dart';
import 'globals.dart';
import 'call_page.dart';
import 'remote_pair_page.dart';
import 'theme/app_theme.dart';

/// 聊天页:气泡消息、长按/右键菜单、多选删除、图片/视频内联显示、
/// 时间分隔条、空状态、输入栏附件面板。
/// 支持两种目标:1:1(peer)与群聊(group)。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.peer, required this.engine, this.group});
  final Peer peer;
  final LittleLawEngine engine;

  /// 非空 = 群聊模式。
  final Group? group;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _subscriptions = <StreamSubscription>[];

  List<Message> _messages = [];
  final _transfers = <String, TransferProgress>{};
  final _selection = <String>{};
  bool _online = false;
  bool _attachOpen = false; // 附件面板展开态(输入栏上方内联撑开)

  bool get _selecting => _selection.isNotEmpty;

  /// 会话标识:群 ID 或对方设备 ID(事件流的 key)。
  String get _convKey => widget.group?.id ?? widget.peer.deviceId;

  bool get _isGroup => widget.group != null;

  @override
  void initState() {
    super.initState();
    final engine = widget.engine;
    _messages = _isGroup ? engine.loadGroupMessages(_convKey) : engine.loadMessages(_convKey);
    _online = !_isGroup && engine.isOnline(_convKey);

    _subscriptions.add(engine.events.listen((e) {
      var changed = false;
      if (e is MessageAdded && e.peerId == _convKey) {
        changed = true;
      } else if (e is MessagesDeleted && e.peerId == _convKey) {
        if (e.clearAll) _selection.clear();
        changed = true;
      } else if (e is PeerStatusChanged && !_isGroup && e.peerId == _convKey) {
        _online = e.online;
        changed = true;
      } else if (e is ClipboardReceived && !_isGroup && e.peerId == _convKey) {
        Clipboard.setData(ClipboardData(text: e.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('对方剪贴板已写入本机剪贴板')),
          );
        }
      }
      if (changed && mounted) {
        setState(() => _messages = _isGroup ? widget.engine.loadGroupMessages(_convKey) : widget.engine.loadMessages(_convKey));
        _scrollToBottom();
      }
    }));

    _subscriptions.add(widget.engine.transferProgress.listen((p) {
      if (p.peerId != _convKey && !_messages.any((m) => m.msgId == p.msgId)) return;
      setState(() {
        _transfers[p.msgId] = p;
        _messages = _isGroup ? widget.engine.loadGroupMessages(_convKey) : widget.engine.loadMessages(_convKey);
      });
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ------------------------------------------------------------ 发送

  /// 发起音视频通话。
  Future<void> _startCall({required bool video}) async {
    final calls = callManager;
    if (calls == null) return;
    if (_isGroup) return;
    await calls.startCall(_convKey, video: video);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallPage(manager: calls),
    ));
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _isGroup ? await widget.engine.sendGroupText(_convKey, text) : await widget.engine.sendText(_convKey, text);
  }

  Future<void> _sendClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('剪贴板为空')));
      return;
    }
    _isGroup ? widget.engine.sendGroupClipboard(_convKey, text) : widget.engine.sendClipboard(_convKey, text);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('剪贴板已发送给对方')));
  }

  Future<void> _pickAndSend(FileType type) async {
    final files = await FilePicker.pickFiles(type: type);
    if (files.isEmpty) return;
    final path = files.single.path;
    if (path == null) return;
    try {
      _isGroup ? await widget.engine.sendGroupFile(_convKey, path) : await widget.engine.sendFile(_convKey, path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    }
  }

  void _showAttachSheet() {
    setState(() => _attachOpen = !_attachOpen);
  }

  /// 输入栏上方内联展开的附件面板(不弹窗,直接撑开)。
  Widget _attachPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _attachAction(Icons.photo_outlined, '图片',
              () => _pickAndSend(FileType.image)),
          _attachAction(Icons.videocam_outlined, '视频',
              () => _pickAndSend(FileType.video)),
          _attachAction(Icons.attach_file_outlined, '文件',
              () => _pickAndSend(FileType.any)),
          _attachAction(Icons.content_paste_go_outlined, '剪贴板',
              _sendClipboard),
        ],
      ),
    );
  }

  Widget _attachAction(IconData icon, String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        setState(() => _attachOpen = false);
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: scheme.primary),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 消息操作

  void _toggleSelect(String msgId) {
    setState(() {
      if (_selection.contains(msgId)) {
        _selection.remove(msgId);
      } else {
        _selection.add(msgId);
      }
    });
  }

  void _copyMessage(Message m) {
    Clipboard.setData(ClipboardData(text: m.text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制')));
  }

  void _copySelection() {
    final texts = _messages
        .where((m) => _selection.contains(m.msgId) && m.kind == Message.kindText)
        .map((m) => m.text)
        .join('\n');
    if (texts.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: texts));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制所选文本')));
    }
    setState(() => _selection.clear());
  }

  Future<void> _deleteSelection() async {
    final ids = _selection.toList();
    setState(() => _selection.clear());
    _isGroup ? await widget.engine.deleteGroupMessages(_convKey, ids) : await widget.engine.deleteMessages(_convKey, ids);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已在双端删除 ${ids.length} 条消息')));
    }
  }

  void _openMessage(Message m) {
    final path = m.filePath;
    if (path == null) return;
    if (m.kind == Message.kindImage) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImageViewerPage(path: path, heroTag: m.msgId),
      ));
    } else if (m.kind == Message.kindVideo) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerPage(path: path, title: m.fileName ?? '视频'),
      ));
    }
  }

  /// 长按/右键上下文菜单。
  void _showMessageMenu(Message m, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        if (m.kind == Message.kindText)
          const PopupMenuItem(value: 'copy', child: _MenuRow(Icons.copy, '复制')),
        if (Message.hasFilePayload(m.kind) &&
            m.fileState == Message.fileStateDone)
          const PopupMenuItem(value: 'open', child: _MenuRow(Icons.open_in_new, '打开')),
        const PopupMenuItem(value: 'select', child: _MenuRow(Icons.checklist, '多选')),
        const PopupMenuItem(
            value: 'delete',
            child: _MenuRow(Icons.delete_outline, '删除(双端)', danger: true)),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      switch (value) {
        case 'copy':
          _copyMessage(m);
        case 'open':
          _openMessage(m);
        case 'select':
          _toggleSelect(m.msgId);
        case 'delete':
          _isGroup ? widget.engine.deleteGroupMessages(_convKey, [m.msgId]) : widget.engine.deleteMessages(_convKey, [m.msgId]);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已在双端删除')));
      }
    });
  }

  // ------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final myId = widget.engine.identity.deviceId;
    final engine = widget.engine;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: _selecting ? _selectionBar() : _normalBar(),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _emptyState()
                : Center(
                    // 桌面宽屏限制聊天流宽度并居中。
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) => _buildItem(ctx, i, myId, engine),
                      ),
                    ),
                  ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: SafeArea(top: false, child: _inputBar()),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _normalBar() {
    final scheme = Theme.of(context).colorScheme;
    final group = widget.group;
    // 群模式头部信息。
    final title = group?.name ?? widget.peer.deviceName;
    final subtitle = group != null
        ? '${group.memberIds.length} 名成员'
        : (_online ? '在线' : '离线(消息将在对方上线后送达)');
    final avatarIcon = group != null
        ? Icons.groups_outlined
        : (widget.peer.platform == 'android' || widget.peer.platform == 'ios'
            ? Icons.smartphone
            : Icons.computer);
    return AppBar(
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primaryContainer,
            child: Icon(avatarIcon,
                size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              Row(
                children: [
                  if (group == null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _online ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        // 语音/视频通话(仅 1:1,任意已连接通道可用)。
        if (_online && !_isGroup) ...[
          IconButton(
            tooltip: '语音通话',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _startCall(video: false),
          ),
          IconButton(
            tooltip: '视频通话',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _startCall(video: true),
          ),
        ],
        // 远程设备(WebRTC 配对,无局域网地址)且离线:提供重连入口。
        if (!_isGroup &&
            !_online &&
            (widget.peer.lastHost == null || widget.peer.lastHost!.isEmpty))
          IconButton(
            tooltip: '重新连接(远程配对)',
            icon: const Icon(Icons.link_outlined),
            onPressed: () {
              final rtc = rtcManager;
              if (rtc == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RemotePairPage(rtc: rtc),
              ));
            },
          ),
        IconButton(
          tooltip: '清空聊天记录(双端)',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: _confirmClearAll,
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar() {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _selection.clear()),
      ),
      title: Text('已选 ${_selection.length} 条'),
      actions: [
        IconButton(
          tooltip: '复制所选文本',
          icon: const Icon(Icons.copy),
          onPressed: _copySelection,
        ),
        IconButton(
          tooltip: '删除(双端)',
          icon: const Icon(Icons.delete_outline),
          onPressed: _deleteSelection,
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('端到端加密会话',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('消息、图片、文件仅存储于两台设备本地\n删除即双端同时销毁',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext ctx, int i, String myId, LittleLawEngine engine) {
    final m = _messages[i];
    final children = <Widget>[];
    // 时间分隔条:首条或与上一条间隔超过 10 分钟。
    if (i == 0 ||
        m.createdAtMs - _messages[i - 1].createdAtMs >
            const Duration(minutes: 10).inMilliseconds) {
      children.add(_TimeDivider(ms: m.createdAtMs));
    }
    children.add(_MessageBubble(
      message: m,
      mine: engine.isFromMe(m.senderId),
      progress: _transfers[m.msgId],
      selected: _selection.contains(m.msgId),
      selecting: _selecting,
      onTap: () {
        if (_selecting) {
          _toggleSelect(m.msgId);
        } else {
          _openMessage(m);
        }
      },
      onLongPress: (pos) {
        if (!_selecting) _showMessageMenu(m, pos);
      },
    ));
    return Column(children: children);
  }

  Widget _inputBar() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // + 按钮:展开/收起附件面板,打开时旋转为 ×。
              IconButton(
                tooltip: '附件',
                icon: AnimatedRotation(
                  turns: _attachOpen ? 0.125 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.add_circle_outline, color: scheme.primary),
                ),
                onPressed: _showAttachSheet,
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: '输入消息…',
                    border: InputBorder.none,
                    isDense: true,
                    filled: false,
                  ),
                  onTap: () {
                    if (_attachOpen) setState(() => _attachOpen = false);
                  },
                  onSubmitted: (_) => _sendText(),
                ),
              ),
              CircleAvatar(
                radius: 19,
                backgroundColor: scheme.primary,
                child: IconButton(
                  tooltip: '发送',
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 17),
                  onPressed: _sendText,
                ),
              ),
            ],
          ),
        ),
        // 附件面板:在输入栏下方内联撑开。
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: _attachOpen
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: _attachPanel(),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录?'),
        content: const Text('将同时在两台设备上删除全部消息,不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('双端清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _isGroup ? await widget.engine.deleteGroupMessages(_convKey, const [], clearAll: true) : await widget.engine.deleteMessages(_convKey, const [], clearAll: true);
    }
  }
}

// ---------------------------------------------------------------------------
// 菜单行
// ---------------------------------------------------------------------------

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : null;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 时间分隔条
// ---------------------------------------------------------------------------

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.ms});
  final int ms;

  @override
  Widget build(BuildContext context) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final text = sameDay
        ? '${two(t.hour)}:${two(t.minute)}'
        : '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 消息气泡
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.progress,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final Message message;
  final bool mine;
  final TransferProgress? progress;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final void Function(Offset position) onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selecting)
          Padding(
            padding: const EdgeInsets.only(top: 14, right: 6),
            child: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? scheme.primary : Colors.grey,
            ),
          ),
        Flexible(
          child: GestureDetector(
            onTap: onTap,
            onLongPressStart: (d) => onLongPress(d.globalPosition),
            onSecondaryTapDown: (d) => onLongPress(d.globalPosition),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: 0.55)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: selected ? const EdgeInsets.all(4) : EdgeInsets.zero,
              child: _content(context, scheme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, ColorScheme scheme) {
    switch (message.kind) {
      case Message.kindImage:
        return _media(context, scheme, image: true);
      case Message.kindVideo:
        return _media(context, scheme, image: false);
      case Message.kindFile:
        return _fileCard(context, scheme);
      default:
        return _textBubble(context, scheme);
    }
  }

  Widget _textBubble(BuildContext context, ColorScheme scheme) {
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: mine ? themeController.skin.gradient : null,
        color: mine ? null : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            message.text,
            style: TextStyle(
              fontSize: 15,
              color: mine ? Colors.white : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _timeText(message.createdAtMs),
            style: TextStyle(
              fontSize: 10,
              color: mine
                  ? Colors.white.withValues(alpha: 0.75)
                  : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 图片/视频气泡。
  Widget _media(BuildContext context, ColorScheme scheme, {required bool image}) {
    final path = message.filePath;
    final transferring = progress != null &&
        progress!.state == TransferProgress.stateRunning;
    final done = message.fileState == Message.fileStateDone && path != null;

    Widget inner;
    if (image && done) {
      inner = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 640, // 缩略解码,避免大图吃内存
        errorBuilder: (_, _, _) => _brokenMedia(),
      );
    } else {
      inner = Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: image
            ? const Icon(Icons.image_outlined, color: Colors.white54, size: 40)
            : Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black45,
                ),
                padding: const EdgeInsets.all(14),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 40),
              ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.62,
        maxHeight: 320,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: image ? 4 / 3 : 16 / 10,
                  child: inner,
                ),
                if (transferring)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(
                        value: progress!.totalBytes > 0
                            ? progress!.doneBytes / progress!.totalBytes
                            : null,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (message.fileState == Message.fileStateFailed)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black38,
                      child: Center(
                        child: Text('传输失败',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${_timeText(message.createdAtMs)} · ${_fileSizeText(message.fileSize)}',
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brokenMedia() {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, size: 40),
    );
  }

  /// 普通文件卡片。
  Widget _fileCard(BuildContext context, ColorScheme scheme) {
    final transferring = progress != null &&
        progress!.state == TransferProgress.stateRunning;
    final fg = mine ? Colors.white : scheme.onSurface;
    final fgDim =
        mine ? Colors.white.withValues(alpha: 0.75) : scheme.outline;
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: mine ? themeController.skin.gradient : null,
        color: mine ? null : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined,
                  size: 32,
                  color: mine ? Colors.white : scheme.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fileName ?? '文件',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                    Text(
                      _fileSizeText(message.fileSize),
                      style: TextStyle(fontSize: 11, color: fgDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (transferring)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: progress!.totalBytes > 0
                    ? progress!.doneBytes / progress!.totalBytes
                    : null,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _fileStateText(),
                style: TextStyle(fontSize: 10, color: fgDim),
              ),
            ),
        ],
      ),
    );
  }

  String _fileStateText() {
    switch (message.fileState) {
      case Message.fileStateDone:
        return '${mine ? "已发送" : "已接收"} · ${_timeText(message.createdAtMs)}';
      case Message.fileStateFailed:
        return '传输失败';
      case Message.fileStateTransferring:
        return '传输中…';
      default:
        return '待传输';
    }
  }

  static String _fileSizeText(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String _timeText(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }
}
