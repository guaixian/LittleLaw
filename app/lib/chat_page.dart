import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'avatar.dart';
import 'media_viewers.dart';
import 'globals.dart';
import 'call_page.dart';
import 'forward_picker.dart';
import 'group_info_page.dart';
import 'i18n.dart';
import 'remote_pair_page.dart';
import 'share_out.dart';
import 'theme/app_theme.dart';

/// 聊天页:气泡消息、长按/右键菜单、多选删除、图片/视频内联显示、
/// 时间分隔条、空状态、输入栏附件面板。
/// 支持两种目标:1:1(peer)与群聊(group);移动端整页 / 桌面嵌入式。
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.peer,
    required this.engine,
    this.group,
    this.embedded = false,
    this.onClose,
  });
  final Peer peer;
  final LittleLawEngine engine;

  /// 非空 = 群聊模式。
  final Group? group;

  /// 桌面三栏嵌入模式(关闭按钮替代返回)。
  final bool embedded;
  final VoidCallback? onClose;

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
  String? _menuMsgId; // 内联消息工具条目标(长按/右键打开)
  bool _dragOver = false; // 桌面拖拽文件悬停高亮
  bool _recording = false; // 语音录制中
  int _recordMs = 0; // 录制时长(毫秒)
  Timer? _recordTicker;
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordPath;
  final Stopwatch _recordWatch = Stopwatch();

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
    engine.markRead(_convKey); // 打开即已读

    _subscriptions.add(engine.events.listen((e) {
      var changed = false;
      if (e is MessageAdded && e.peerId == _convKey) {
        changed = true;
        engine.markRead(_convKey); // 会话打开时新消息自动已读
      } else if (e is MessagesDeleted && e.peerId == _convKey) {
        if (e.clearAll) _selection.clear();
        changed = true;
      } else if (e is PeerStatusChanged && !_isGroup && e.peerId == _convKey) {
        _online = e.online;
        changed = true;
      } else if (e is MessageStateChanged &&
          _messages.any((m) => m.msgId == e.msgId)) {
        changed = true; // 发送状态变化(发送中/成功/失败)
      } else if (e is ReceiptsUpdated && e.convKey == _convKey) {
        changed = true; // 自己的消息被对方读了
      } else if (e is ReactionsChanged && e.convKey == _convKey) {
        changed = true; // 表情回应更新
      } else if (e is ClipboardReceived && !_isGroup && e.peerId == _convKey) {
        Clipboard.setData(ClipboardData(text: e.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.t('chat.clipRecvToast'))),
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
    widget.engine.markRead(_convKey);
    _recordTicker?.cancel();
    if (_recording) {
      // 页面销毁时终止录制并丢弃草稿。
      unawaited(_recorder.stop());
      unawaited(_recorder.dispose());
    }
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
    await _sendPath(path);
  }

  Future<void> _sendPath(String path) async {
    try {
      _isGroup ? await widget.engine.sendGroupFile(_convKey, path) : await widget.engine.sendFile(_convKey, path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    }
  }

  // ------------------------------------------------------------ 语音消息

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecord(send: true);
    } else {
      await _startRecord();
    }
  }

  Future<void> _startRecord() async {
    try {
      final granted = await _recorder.hasPermission();
      if (!granted) return;
      final tmp = await getTemporaryDirectory();
      _recordPath =
          '${tmp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: _recordPath!,
      );
      _recordWatch
        ..reset()
        ..start();
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() => _recordMs = _recordWatch.elapsedMilliseconds);
      });
      setState(() {
        _recording = true;
        _recordMs = 0;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法启动录音(缺少麦克风权限)')));
      }
    }
  }

  Future<void> _stopRecord({required bool send}) async {
    _recordTicker?.cancel();
    _recordWatch.stop();
    final ms = _recordWatch.elapsedMilliseconds;
    setState(() => _recording = false);
    try {
      final path = await _recorder.stop();
      if (send && path != null && ms >= 600) {
        // 短于 0.6s 的录音视为误触丢弃。
        _isGroup
            ? await widget.engine.sendGroupVoice(_convKey, path, ms)
            : await widget.engine.sendVoice(_convKey, path, ms);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------ 表情回应

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  void _react(Message m, String emoji) {
    final mine = m.reactions[widget.engine.identity.deviceId];
    widget.engine.setReaction(_convKey, m.msgId, mine == emoji ? '' : emoji);
  }

  // ------------------------------------------------------------ 粘贴发送

  /// 粘贴板内容进会话:剪贴板有图片(Windows 截图等)直接发图,
  /// 否则有文本则填入输入框。
  Future<void> _pasteAndSend() async {
    final imagePath = await ShareOut.clipboardImagePath();
    if (imagePath != null) {
      await _sendPath(imagePath);
      return;
    }
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      setState(() => _input.text = text);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(L10n.t('chat.pasteEmpty'))));
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
          _attachAction(Icons.photo_outlined, L10n.t('chat.image'),
              () => _pickAndSend(FileType.image)),
          _attachAction(Icons.videocam_outlined, L10n.t('chat.video'),
              () => _pickAndSend(FileType.video)),
          _attachAction(Icons.attach_file_outlined, L10n.t('chat.file'),
              () => _pickAndSend(FileType.any)),
          _attachAction(Icons.content_paste_go_outlined, L10n.t('chat.clipboard'),
              _sendClipboard),
          _attachAction(Icons.content_paste_outlined, L10n.t('chat.pasteSend'), _pasteAndSend),
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
        .showSnackBar(SnackBar(content: Text(L10n.t('chat.copiedToast'))));
  }

  void _copySelection() {
    final texts = _messages
        .where((m) => _selection.contains(m.msgId) && m.kind == Message.kindText)
        .map((m) => m.text)
        .join('\n');
    if (texts.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: texts));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L10n.t('chat.copiedToast'))));
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

  /// 供查看/打开/转发/分享的明文路径(vault 开启时解密到缓存)。
  Future<String?> _plainPathOf(Message m) async {
    if (m.filePath == null ||
        m.fileState != Message.fileStateDone) {
      return null;
    }
    try {
      return await widget.engine.plaintextPathFor(m);
    } catch (_) {
      return null;
    }
  }

  void _openMessage(Message m) async {
    final path = await _plainPathOf(m);
    if (!mounted || path == null) return;
    if (m.kind == Message.kindImage) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImageViewerPage(path: path, heroTag: m.msgId),
      ));
    } else if (m.kind == Message.kindVideo) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
            path: path, title: m.fileName ?? L10n.t('chat.video')),
      ));
    }
  }

  /// 长按/右键:在消息上方展开内联工具条(表情 + 小功能按钮)。
  void _showMessageMenu(Message m, Offset position) {
    setState(() => _menuMsgId = (_menuMsgId == m.msgId) ? null : m.msgId);
  }

  /// 内联工具条:emoji + 复制/打开/转发/分享/多选/删除。
  Widget _inlineToolbar(Message m) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final emoji in _quickReactions)
              _barBtn(Text(emoji, style: const TextStyle(fontSize: 17)),
                  () {
                _react(m, emoji);
                setState(() => _menuMsgId = null);
              }),
            const VerticalDivider(width: 8),
            if (m.kind == Message.kindText)
              _barBtn(const Icon(Icons.copy, size: 15), () {
                _copyMessage(m);
                setState(() => _menuMsgId = null);
              }),
            if (Message.hasFilePayload(m.kind) &&
                m.fileState == Message.fileStateDone) ...[
              _barBtn(const Icon(Icons.open_in_new, size: 15), () {
                _openMessage(m);
                setState(() => _menuMsgId = null);
              }),
              // 桌面:资源管理器定位;手机:系统"打开方式"。
              _barBtn(
                Icon(
                  Platform.isWindows || Platform.isMacOS || Platform.isLinux
                      ? Icons.folder_open
                      : Icons.open_with,
                  size: 15,
                ),
                () async {
                  setState(() => _menuMsgId = null);
                  final plain = await _plainPathOf(m);
                  if (plain == null) return;
                  if (Platform.isAndroid) {
                    await ShareOut.openWithOther(plain);
                  } else {
                    await ShareOut.revealInFolder(plain);
                  }
                },
              ),
            ],
            if (m.kind == Message.kindText ||
                (Message.hasFilePayload(m.kind) &&
                    m.fileState == Message.fileStateDone)) ...[
              _barBtn(const Icon(Icons.shortcut, size: 15), () async {
                setState(() => _menuMsgId = null);
                if (m.kind == Message.kindText) {
                  showForwardPicker(widget.engine, text: m.text);
                } else {
                  final plain = await _plainPathOf(m);
                  if (plain != null) {
                    showForwardPicker(widget.engine, filePath: plain);
                  }
                }
              }),
              _barBtn(const Icon(Icons.ios_share, size: 15), () async {
                setState(() => _menuMsgId = null);
                if (m.kind == Message.kindText) {
                  ShareOut.shareText(m.text);
                } else {
                  final plain = await _plainPathOf(m);
                  if (plain != null) ShareOut.shareFile(plain);
                }
              }),
            ],
            _barBtn(const Icon(Icons.checklist, size: 15), () {
              setState(() {
                if (!_selecting) _toggleSelect(m.msgId);
                _menuMsgId = null;
              });
            }),
            _barBtn(Icon(Icons.delete_outline, size: 15, color: scheme.error),
                () {
              setState(() => _menuMsgId = null);
              _isGroup
                  ? widget.engine
                      .deleteGroupMessages(_convKey, [m.msgId])
                  : widget.engine.deleteMessages(_convKey, [m.msgId]);
            }),
          ],
        ),
      ),
    );
  }

  Widget _barBtn(Widget child, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = widget.engine.identity.deviceId;
    final engine = widget.engine;
    final scheme = Theme.of(context).colorScheme;
    Widget page = Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
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
                      child: GestureDetector(
                        onTap: () => setState(() => _menuMsgId = null),
                        behavior: HitTestBehavior.translucent,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) =>
                              _buildItem(ctx, i, myId, engine),
                        ),
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
    // 桌面:拖拽文件进窗口直接发送。
    return DropTarget(
      onDragDone: (details) {
        for (final f in details.files) {
          unawaited(_sendPath(f.path));
        }
      },
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragUpdated: (_) {},
      child: Stack(
        children: [
          page,
          if (_dragOver)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: scheme.primary.withValues(alpha: 0.08),
                  child: Center(
                    child: Icon(Icons.download_rounded,
                        size: 64, color: scheme.primary.withValues(alpha: 0.5)),
                  ),
                ),
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
        : (_online ? L10n.t('common.online') : L10n.t('chat.offlineHint'));
    final avatarImg = group != null
        ? Avatars.imageOf(widget.engine, groupId: group.id)
        : Avatars.imageOf(widget.engine, peerId: widget.peer.deviceId);
    final avatarIcon = group != null
        ? Icons.groups_outlined
        : (widget.peer.platform == 'android' || widget.peer.platform == 'ios'
            ? Icons.smartphone
            : Icons.computer);
    return AppBar(
      leading: widget.embedded
          ? IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            )
          : null,
      title: GestureDetector(
        onTap: _isGroup
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupInfoPage(
                      engine: widget.engine, groupId: widget.group!.id),
                ))
            : null,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primaryContainer,
              backgroundImage: avatarImg,
              child: avatarImg == null
                  ? Icon(avatarIcon,
                      size: 20, color: scheme.onPrimaryContainer)
                  : null,
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
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        // 语音/视频通话(仅 1:1,任意已连接通道可用)。
        if (_online && !_isGroup) ...[
          IconButton(
            tooltip: L10n.t('chat.audioCall'),
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _startCall(video: false),
          ),
          IconButton(
            tooltip: L10n.t('chat.videoCall'),
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _startCall(video: true),
          ),
        ],
        // 远程设备(WebRTC 配对,无局域网地址)且离线:提供重连入口。
        if (!_isGroup &&
            !_online &&
            (widget.peer.lastHost == null || widget.peer.lastHost!.isEmpty))
          IconButton(
            tooltip: L10n.t('chat.reconnect'),
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
          tooltip: L10n.t('chat.clearAll'),
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
          Text(L10n.t('chat.e2eTitle'),
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(L10n.t('chat.e2eBody'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext ctx, int i, String myId, LittleLawEngine engine) {
    final m = _messages[i];
    final children = <Widget>[];
    final mine = engine.isFromMe(m.senderId);
    // 消息分组:与上一条同发送者且间隔 < 4 分钟 → 隐藏发送者名与头像间距收紧。
    final grouped = i > 0 &&
        _messages[i - 1].senderId == m.senderId &&
        m.createdAtMs - _messages[i - 1].createdAtMs <
            const Duration(minutes: 4).inMilliseconds;
    // 时间分隔条:首条或与上一条间隔超过 30 分钟。
    if (i == 0 ||
        m.createdAtMs - _messages[i - 1].createdAtMs >
            const Duration(minutes: 30).inMilliseconds) {
      children.add(_TimeDivider(ms: m.createdAtMs));
    }
    final bubble = _MessageBubble(
      message: m,
      mine: mine,
      showSender: !grouped,
      senderName: _isGroup && !mine
          ? (engine.peerById(m.senderId)?.deviceName ?? '群成员')
          : null,
      progress: _transfers[m.msgId],
      selected: _selection.contains(m.msgId),
      selecting: _selecting,
      avatarIcon: _avatarIcon(mine, m.senderId),
      avatarImage: mine
          ? Avatars.imageOf(engine)
          : Avatars.imageOf(engine, peerId: m.senderId),
      onResend: mine ? () => widget.engine.resendMessage(m.msgId) : null,
      onReaction: (emoji) => _react(m, emoji),
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
    );
    // 工具条悬浮在消息上方(覆盖式,不挤占布局)。
    children.add(_menuMsgId == m.msgId
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              bubble,
              Positioned(
                top: -34,
                left: 0,
                child: _inlineToolbar(m),
              ),
            ],
          )
        : bubble);
    return Column(children: children);
  }

  IconData _avatarIcon(bool mine, String senderId) {
    if (mine) return Icons.person;
    final p = widget.engine.peerById(senderId);
    return (p?.platform == 'android' || p?.platform == 'ios')
        ? Icons.smartphone
        : Icons.computer_outlined;
  }

  Widget _inputBar() {
    final scheme = Theme.of(context).colorScheme;
    if (_recording) {
      // 录音态:红色脉冲 + 时长 + 取消/发送。
      return Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.fiber_manual_record,
                color: scheme.error, size: 16),
            const SizedBox(width: 8),
            Text(
              '录音中 ${(_recordMs / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _stopRecord(send: false),
              child: Text(L10n.t('common.cancel')),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: () => _stopRecord(send: true),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(L10n.t('chat.send')),
            ),
          ],
        ),
      );
    }
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
                tooltip: L10n.t('chat.attach'),
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
                  decoration: InputDecoration(
                    hintText: L10n.t('chat.inputHint'),
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
              // 麦克风:点击开始录音,再点完成发送。
              IconButton(
                tooltip: L10n.t('chat.voiceMsg'),
                icon: Icon(Icons.mic_none_rounded, color: scheme.primary),
                onPressed: _toggleRecord,
              ),
              const SizedBox(width: 2),
              CircleAvatar(
                radius: 19,
                backgroundColor: scheme.primary,
                child: IconButton(
                  tooltip: L10n.t('chat.send'),
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
    required this.avatarIcon,
    this.avatarImage,
    this.onResend,
    this.senderName,
    this.showSender = true,
    this.onReaction,
  });

  final Message message;
  final bool mine;
  final String? senderName; // 群消息:发送者名(自己为 null)
  final bool showSender; // 分组中隐藏发送者名(头像仍显示)
  final IconData avatarIcon;
  final ImageProvider? avatarImage;
  final VoidCallback? onResend; // 发送失败重发(仅自己消息)
  final TransferProgress? progress;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final void Function(Offset position) onLongPress;
  final void Function(String emoji)? onReaction;

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
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.secondaryContainer,
              child: Icon(avatarIcon,
                  size: 16, color: scheme.onSecondaryContainer),
            ),
          ),
        Flexible(
          child: GestureDetector(
            onTap: onTap,
            onLongPressStart: (d) => onLongPress(d.globalPosition),
            onSecondaryTapDown: (d) => onLongPress(d.globalPosition),
            child: Container(
              margin: EdgeInsets.symmetric(
                  vertical: showSender ? 3 : 1, horizontal: 2),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: 0.55)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: selected ? const EdgeInsets.all(4) : EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: mine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (senderName != null && showSender)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 1),
                      child: Text(senderName!,
                          style: TextStyle(
                              fontSize: 11, color: scheme.primary)),
                    ),
                  _content(context, scheme),
                  if (message.reactions.isNotEmpty)
                    _reactionChips(context, scheme),
                ],
              ),
            ),
          ),
        ),
        if (mine)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 8),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primaryContainer,
              child: Icon(avatarIcon,
                  size: 16, color: scheme.onPrimaryContainer),
            ),
          ),
      ],
    );
  }

  /// 表情回应角标:按 emoji 聚合计数,点击切换自己的回应。
  Widget _reactionChips(BuildContext context, ColorScheme scheme) {
    final aggregated = <String, List<String>>{};
    message.reactions.forEach((device, emoji) {
      aggregated.putIfAbsent(emoji, () => []).add(device);
    });
    final entries = aggregated.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        children: [
          for (final e in entries)
            GestureDetector(
              onTap: onReaction != null ? () => onReaction!(e.key) : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.key, style: const TextStyle(fontSize: 13)),
                    if (e.value.length > 1) ...[
                      const SizedBox(width: 3),
                      Text('${e.value.length}',
                          style: TextStyle(
                              fontSize: 11, color: scheme.outline)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 自己消息的发送状态:⏱发送中 / !失败(点击重发) / ✓送达 / ✓✓已读。
  Widget _statusIcon() {
    if (!mine) return const SizedBox.shrink();
    if (message.sendState == Message.sendFailed) {
      return GestureDetector(
        onTap: onResend,
        child: const Icon(Icons.error_outline,
            size: 14, color: Color(0xFFFF6B6B)),
      );
    }
    if (message.sendState == Message.sendSending) {
      return const Icon(Icons.schedule, size: 12, color: Colors.white60);
    }
    return Icon(
      message.read ? Icons.done_all : Icons.done,
      size: 13,
      color: message.read ? Colors.lightBlueAccent : Colors.white60,
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
      case Message.kindVoice:
        return _voiceBubble(context, scheme);
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _timeText(message.createdAtMs),
                style: TextStyle(
                  fontSize: 10,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.75)
                      : scheme.outline,
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 3),
                _statusIcon(),
              ],
            ],
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fileStateText(),
                    style: TextStyle(fontSize: 10, color: fgDim),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    _statusIcon(),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 语音气泡:播放按钮 + 时长 + 播放进度。
  Widget _voiceBubble(BuildContext context, ColorScheme scheme) {
    return _VoiceBubble(
      message: message,
      mine: mine,
      transferring: progress != null &&
          progress!.state == TransferProgress.stateRunning,
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

// ---------------------------------------------------------------------------
// 语音气泡(独立 StatefulWidget:持有 media_kit 播放器)
// ---------------------------------------------------------------------------

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble(
      {required this.message, required this.mine, required this.transferring});
  final Message message;
  final bool mine;
  final bool transferring;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  Player? _player;
  bool _playing = false;
  double _progress = 0;
  StreamSubscription? _sub;

  static String _durationText(int ms) {
    final s = (ms / 1000).ceil();
    return '$s"';
  }

  Future<void> _toggle() async {
    final engine = activeEngine;
    if (engine == null ||
        widget.message.fileState != Message.fileStateDone) {
      return;
    }
    String path;
    try {
      path = await engine.plaintextPathFor(widget.message);
    } catch (_) {
      return;
    }
    if (_playing) {
      await _player?.pause();
      return;
    }
    _player ??= () {
      final p = Player();
      _sub = p.stream.position.listen((pos) {
        final dur = widget.message.durationMs > 0
            ? widget.message.durationMs / 1000
            : (p.state.duration.inMilliseconds / 1000);
        if (dur > 0 && mounted) {
          setState(() => _progress = (pos.inMilliseconds / 1000 / dur)
              .clamp(0.0, 1.0));
        }
      });
      return p;
    }();
    if (_player!.state.playlist.medias.isEmpty ||
        _player!.state.playlist.medias.first.uri != path) {
      await _player!.open(Media(path));
    } else {
      await _player!.play();
    }
    if (mounted) setState(() => _playing = true);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future.value());
    unawaited(_player?.dispose() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fgDim =
        widget.mine ? Colors.white.withValues(alpha: 0.75) : scheme.outline;
    final dur = _durationText(
        widget.message.durationMs > 0 ? widget.message.durationMs : 1000);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: widget.mine ? themeController.skin.gradient : null,
        color: widget.mine ? null : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.mine
                    ? Colors.white.withValues(alpha: 0.2)
                    : scheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: widget.mine ? Colors.white : scheme.primary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 语音波形示意(静态条) + 进度高亮。
          SizedBox(
            width: 90,
            height: 22,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final h in const [8.0, 14.0, 10.0, 18.0, 12.0, 16.0, 9.0])
                      Container(
                        width: 3,
                        height: h,
                        decoration: BoxDecoration(
                          color: fgDim,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
                FractionallySizedBox(
                  widthFactor: _progress,
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        scheme.primary.withValues(alpha: 0.65),
                        scheme.primary.withValues(alpha: 0.2),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(dur, style: TextStyle(fontSize: 12, color: fgDim)),
          if (widget.mine) ...[
            const SizedBox(width: 4),
            widget.message.read
                ? const Icon(Icons.done_all,
                    size: 13, color: Colors.lightBlueAccent)
                : Icon(Icons.done, size: 13, color: fgDim),
          ],
          if (widget.transferring)
            const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}
