import 'dart:async';

import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'chat_page.dart';
import 'globals.dart';
import 'group_create_page.dart';
import 'group_info_page.dart';
import 'i18n.dart';
import 'main.dart' show ConnectPage, ProfilePage;
import 'search_page.dart';
import 'theme/app_theme.dart';

/// 桌面端三栏外壳(Telegram/微信 PC 式):
/// 图标栏 | 会话列表(或连接/我的) | 聊天面板。
class AdaptiveHomeShell extends StatefulWidget {
  const AdaptiveHomeShell({super.key});

  @override
  State<AdaptiveHomeShell> createState() => _AdaptiveHomeShellState();
}

class _AdaptiveHomeShellState extends State<AdaptiveHomeShell> {
  int _tab = 0; // 0=聊天 1=连接 2=我的
  String? _activeKey; // 打开的会话(群 ID 或对方设备 ID)
  final _subscriptions = <StreamSubscription>[];

  LittleLawEngine get engine => activeEngine!;

  @override
  void initState() {
    super.initState();
    final e = activeEngine!;
    _subscriptions.add(e.events.listen((ev) {
      if (ev is MessageAdded ||
          ev is MessagesDeleted ||
          ev is PeerStatusChanged ||
          ev is GroupSynced ||
          ev is ReceiptsUpdated ||
          ev is ReactionsChanged) {
        if (mounted) setState(() {});
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 连接/设置页独占剩余全部宽度(不出现右侧空栏)。
    if (_tab == 1) {
      return Scaffold(
        body: Row(
          children: [
            _iconRail(scheme),
            VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(
              child: Scaffold(
                backgroundColor: scheme.surfaceContainerLowest,
                appBar: AppBar(title: Text(L10n.t('nav.connect'))),
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: const ConnectPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_tab == 2) {
      return Scaffold(
        body: Row(
          children: [
            _iconRail(scheme),
            VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(
              child: Scaffold(
                backgroundColor: scheme.surfaceContainerLowest,
                appBar: AppBar(title: Text(L10n.t('nav.settings'))),
                // 宽屏限宽居中,避免卡片横贯整屏。
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: const ProfilePage(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          _iconRail(scheme),
          SizedBox(width: 320, child: _conversationPane(scheme)),
          VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
          Expanded(child: _rightPane(scheme)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 图标栏

  Widget _iconRail(ColorScheme scheme) {
    final skin = themeController.skin;
    Widget item(IconData icon, String label, int index) {
      final selected = _tab == index;
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _tab = index;
            if (index != 0) _activeKey = null;
          }),
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: selected ? skin.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 64,
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: skin.gradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                const Icon(Icons.lock_rounded, color: Colors.white, size: 19),
          ),
          const SizedBox(height: 14),
          item(Icons.forum_outlined, L10n.t('nav.chats'), 0),
          item(Icons.hub_outlined, L10n.t('nav.connect'), 1),
          const Spacer(),
          // 设置固定在图标栏底部(搜索入口在会话列表头部)。
          item(Icons.settings_outlined, L10n.t('nav.settings'), 2),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 中栏

  /// 会话列表:群 + 已配对设备,按最后消息时间排序。
  Widget _conversationPane(ColorScheme scheme) {
    final summaries = engine.conversationSummaries();
    final summaryByConv = {for (final s in summaries) s.convId: s};

    final entries = <_ConvEntry>[];
    for (final g in engine.groups) {
      final s = summaryByConv[Group.convIdOf(g.id)];
      entries.add(_ConvEntry(
        key: g.id,
        isGroup: true,
        title: g.name,
        atMs: s?.atMs ?? g.createdAtMs,
        unread: s?.unread ?? 0,
        preview: s == null ? '' : _previewOf(s),
      ));
    }
    for (final p in engine.peers) {
      final s = summaryByConv[Store.convIdFor(engine.identity.deviceId, p.deviceId)];
      entries.add(_ConvEntry(
        key: p.deviceId,
        isGroup: false,
        title: p.deviceName,
        atMs: s?.atMs ?? 0,
        unread: s?.unread ?? 0,
        preview: s == null ? '' : _previewOf(s),
        online: engine.isOnline(p.deviceId),
        subtitle: p.deviceModel.isNotEmpty ? p.deviceModel : p.platform,
      ));
    }
    entries.sort((a, b) => b.atMs.compareTo(a.atMs));

    return Column(
      children: [
        // 头部:标题 + 新建群 + 搜索。
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(L10n.t('nav.chats'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: L10n.t('common.search'),
                icon: Icon(Icons.search, size: 20, color: scheme.primary),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SearchPage(engine: engine))),
              ),
              IconButton(
                tooltip: L10n.t('devices.newGroup'),
                icon: Icon(Icons.group_add_outlined,
                    size: 20, color: scheme.primary),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GroupCreatePage(engine: engine))),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (ctx, i) {
              final e = entries[i];
              final selected = _activeKey == e.key && _tab == 0;
              return _convTile(e, selected, scheme);
            },
          ),
        ),
      ],
    );
  }

  String _previewOf(ConvSummary s) {
    return switch (s.kind) {
      Message.kindImage => '[${L10n.t('chat.image')}]',
      Message.kindVideo => '[${L10n.t('chat.video')}]',
      Message.kindVoice => '[${L10n.t('chat.voiceMsg')}]',
      Message.kindFile =>
        '[${L10n.t('chat.file')}] ${s.fileName ?? s.text}',
      _ => s.text,
    };
  }

  Widget _convTile(_ConvEntry e, bool selected, ColorScheme scheme) {
    Widget avatar;
    if (e.isGroup) {
      avatar = CircleAvatar(
        radius: 21,
        backgroundColor: scheme.primaryContainer,
        child: Icon(Icons.groups_outlined,
            size: 21, color: scheme.onPrimaryContainer),
      );
    } else {
      avatar = CircleAvatar(
        radius: 21,
        backgroundColor: scheme.secondaryContainer,
        child: Icon(Icons.smartphone,
            size: 20, color: scheme.onSecondaryContainer),
      );
    }
    return InkWell(
      onTap: () => setState(() {
        _tab = 0;
        _activeKey = e.key;
      }),
      onLongPress: () => _convMenu(e),
      onSecondaryTapDown: (d) => _convMenu(e, position: d.globalPosition),
      child: Container(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                if (!e.isGroup && (e.online ?? false))
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                        border: Border.all(
                            color: scheme.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      if (e.atMs > 0)
                        Text(_timeText(e.atMs),
                            style: TextStyle(
                                fontSize: 11, color: scheme.outline)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.preview.isEmpty
                              ? (e.subtitle ?? L10n.t('devices.tapToChat'))
                              : e.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (e.unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            '${e.unread > 99 ? '99+' : e.unread}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeText(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '${two(t.hour)}:${two(t.minute)}' : '${t.month}/${t.day}';
  }

  // ------------------------------------------------------------ 会话菜单

  /// 右键/长按会话:清空记录(双端);群聊另有退出/群资料。
  void _convMenu(_ConvEntry e, {Offset? position}) {
    if (e.isGroup) {
      final g = engine.groupById(e.key);
      if (g == null) return;
      if (position == null) {
        // 移动端:底部动作面板。
        showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(L10n.t('group.info')),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          GroupInfoPage(engine: engine, groupId: e.key),
                    ));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(L10n.t('chat.clearAll')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmClear(e);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  title: Text(L10n.t('group.leave')),
                  onTap: () {
                    Navigator.pop(ctx);
                    engine.leaveGroup(e.key);
                  },
                ),
              ],
            ),
          ),
        );
        return;
      }
      _popupMenu(e, position);
      return;
    }
    if (position == null) {
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(L10n.t('chat.clearAll')),
            onTap: () {
              Navigator.pop(ctx);
              _confirmClear(e);
            },
          ),
        ),
      );
      return;
    }
    _popupMenu(e, position);
  }

  void _popupMenu(_ConvEntry e, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (e.isGroup)
          const PopupMenuItem(
              value: 'info', child: Text('群资料')),
        PopupMenuItem(
            value: 'clear', child: Text(L10n.t('chat.clearAll'))),
        if (e.isGroup)
          PopupMenuItem(
              value: 'leave', child: Text(L10n.t('group.leave'))),
      ],
    ).then((v) {
      if (!mounted || v == null) return;
      switch (v) {
        case 'info':
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupInfoPage(engine: engine, groupId: e.key),
          ));
        case 'clear':
          _confirmClear(e);
        case 'leave':
          engine.leaveGroup(e.key);
          if (_activeKey == e.key) setState(() => _activeKey = null);
      }
    });
  }

  Future<void> _confirmClear(_ConvEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('chat.clearAll')),
        content: Text(L10n.t('chat.clearConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L10n.t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L10n.t('chat.deleteForAll'))),
        ],
      ),
    );
    if (ok != true) return;
    if (e.isGroup) {
      await engine.deleteGroupMessages(e.key, const [], clearAll: true);
    } else {
      await engine.deleteMessages(e.key, const [], clearAll: true);
    }
    if (_activeKey == e.key) setState(() => _activeKey = null);
  }

  // ------------------------------------------------------------ 右栏

  Widget _rightPane(ColorScheme scheme) {
    if (_activeKey == null) {
      return Container(
        color: scheme.surfaceContainerLowest,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 52, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              Text(L10n.t('chat.e2eTitle'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(L10n.t('chat.selectPlaceholder'),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }
    final key = _activeKey!;
    final g = engine.groupById(key);
    if (g != null && engine.peers.isNotEmpty) {
      return ChatPage(
        peer: engine.peers.first,
        engine: engine,
        group: g,
        embedded: true,
        onClose: () => setState(() => _activeKey = null),
      );
    }
    final peer = engine.peerById(key);
    if (peer != null) {
      return ChatPage(
        peer: peer,
        engine: engine,
        embedded: true,
        onClose: () => setState(() => _activeKey = null),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ConvEntry {
  _ConvEntry({
    required this.key,
    required this.isGroup,
    required this.title,
    required this.atMs,
    required this.unread,
    required this.preview,
    this.online,
    this.subtitle,
  });

  final String key;
  final bool isGroup;
  final String title;
  final int atMs;
  final int unread;
  final String preview;
  final bool? online;
  final String? subtitle;
}
