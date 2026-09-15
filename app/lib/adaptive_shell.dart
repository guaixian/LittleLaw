import 'dart:async';

import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'chat_page.dart';
import 'avatar.dart';
import 'globals.dart';
import 'group_create_page.dart';
import 'group_info_page.dart';
import 'i18n.dart';
import 'main.dart'
    show ConnectPage, ProfilePage, startPairFlow;
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
  int _tab = 0; // 0=聊天 1=连接 2=设置
  String? _activeKey; // 打开的会话(群 ID 或对方设备 ID)
  final _subscriptions = <StreamSubscription>[];
  final _discovered = <String, DiscoveredDevice>{};

  /// 当前网络组播是否被禁(禁用时发现依赖子网扫描,提示用户)。
  bool _mcastOk = true;

  /// 事件风暴下的刷新合并:群消息高峰每条事件全量 setState + 重建
  /// (每次 build 重查 conversationSummaries),改为 120ms 合并一次。
  Timer? _refreshTimer;

  LittleLawEngine get engine => activeEngine!;

  @override
  void initState() {
    super.initState();
    final e = activeEngine!;
    _subscriptions.add(e.events.listen((ev) {
      if (ev is MessageAdded ||
          ev is MessagesDeleted ||
          ev is PeerStatusChanged ||
          ev is PeerRemoved ||
          ev is GroupSynced ||
          ev is ReceiptsUpdated ||
          ev is ReactionsChanged ||
          ev is ProfileUpdated) {
        if (ev is ProfileUpdated) Avatars.invalidate();
        _scheduleRefresh();
      }
    }));
    // 附近的设备(未配对):桌面端配对入口。
    _subscriptions.add(e.discoveredDevices.listen((d) {
      if (e.peerById(d.deviceId) != null) return;
      if (mounted) setState(() => _discovered[d.deviceId] = d);
    }));
    _subscriptions.add(e.discovery.expiredDevices.listen((id) {
      if (_discovered.remove(id) != null && mounted) setState(() {});
    }));
    // 组播健康:被禁时提示(发现退化为子网扫描,大子网可能遗漏)。
    _mcastOk = e.discovery.multicastJoined;
    _subscriptions.add(e.discovery.multicastHealth.listen((ok) {
      if (mounted) setState(() => _mcastOk = ok);
    }));
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
          onTap: () => setState(() => _tab = index),
          // 保留 _activeKey:点一下设置再回来,聊天面板/草稿不丢
          //(旧版强制清空,回来变占位页)。
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
          // 顶部:我的头像(点击跳设置修改)。
          GestureDetector(
            onTap: () => setState(() => _tab = 2),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: Avatars.imageOf(engine) == null
                    ? themeController.skin.gradient
                    : null,
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                    width: 1.5),
                image: Avatars.imageOf(engine) != null
                    ? DecorationImage(
                        image: Avatars.imageOf(engine)!, fit: BoxFit.cover)
                    : null,
              ),
              child: Avatars.imageOf(engine) == null
                  ? const Icon(Icons.person,
                      color: Colors.white, size: 20)
                  : null,
            ),
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
      if (s == null) continue; // 无消息的 1:1 不显示(删除会话后即消失)
      entries.add(_ConvEntry(
        key: p.deviceId,
        isGroup: false,
        title: p.deviceName,
        atMs: s.atMs,
        unread: s.unread,
        preview: _previewOf(s),
        online: engine.isOnline(p.deviceId),
        subtitle: p.deviceModel.isNotEmpty ? p.deviceModel : p.platform,
      ));
    }
    entries.sort((a, b) => b.atMs.compareTo(a.atMs));
    // 已配对但还没有会话的设备(刚配对完/清空过记录):常驻区块,点开即聊。
    final pairedNoConv = <Peer>[];
    for (final p in engine.peers) {
      final s =
          summaryByConv[Store.convIdFor(engine.identity.deviceId, p.deviceId)];
      if (s == null) pairedNoConv.add(p);
    }
    // 渲染时过滤:已配对设备绝不出现在"附近"列表(配对瞬间即消失)。
    _discovered.removeWhere((id, d) => engine.peerById(id) != null);
    final discovered = _discovered.values.toList();

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
            itemCount: entries.length +
                (pairedNoConv.isEmpty ? 0 : 1 + pairedNoConv.length) +
                1 +
                discovered.length,
            itemBuilder: (ctx, i) {
              if (i < entries.length) {
                final e = entries[i];
                final selected = _activeKey == e.key && _tab == 0;
                return _convTile(e, selected, scheme);
              }
              var j = i - entries.length;
              // 已配对设备(无会话)。
              if (pairedNoConv.isNotEmpty && j < 1 + pairedNoConv.length) {
                if (j == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                    child: Text(L10n.t('devices.paired'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant)),
                  );
                }
                final p = pairedNoConv[j - 1];
                final pAvatar = Avatars.imageOf(engine, peerId: p.deviceId);
                return GestureDetector(
                  onLongPress: () => _confirmUnpair(p.deviceId, p.deviceName),
                  onSecondaryTapDown: (d) =>
                      _confirmUnpair(p.deviceId, p.deviceName),
                  child: ListTile(
                  dense: true,
                  onTap: () => setState(() {
                    _tab = 0;
                    _activeKey = p.deviceId;
                  }),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.secondaryContainer,
                    backgroundImage: pAvatar,
                    child: pAvatar == null
                        ? Icon(
                            p.platform == 'android' || p.platform == 'ios'
                                ? Icons.smartphone
                                : Icons.computer_outlined,
                            size: 17,
                            color: scheme.onSecondaryContainer)
                        : null,
                  ),
                  title: Text(p.deviceName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(L10n.t('devices.tapToChat'),
                      style: const TextStyle(fontSize: 12)),
                  trailing: engine.isOnline(p.deviceId)
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Colors.green),
                        )
                      : null,
                  ),
                );
              }
              if (pairedNoConv.isNotEmpty) j -= 1 + pairedNoConv.length;
              if (j == 0) {
                // 附近的设备:常驻区块(空态显示提示 + 手动刷新)。
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(L10n.t('devices.nearby'),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant)),
                      ),
                      IconButton(
                        tooltip: L10n.t('common.search'),
                        icon: Icon(Icons.refresh,
                            size: 18, color: scheme.primary),
                        onPressed: () {
                          engine.discovery.rescan();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }
              final d = discovered[j - 1];
              // 附近的设备(未配对):点击配对;曾配对过(有本地头像)则显示头像。
              final dAvatar = Avatars.imageOf(engine, peerId: d.deviceId);
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.secondaryContainer,
                  backgroundImage: dAvatar,
                  child: dAvatar == null
                      ? Icon(Icons.add,
                          size: 18, color: scheme.onSecondaryContainer)
                      : null,
                ),
                title: Text(d.info.deviceName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  d.info.deviceModel.isNotEmpty
                      ? d.info.deviceModel
                      : (d.info.platform.isNotEmpty ? d.info.platform : d.host),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    await startPairFlow(d);
                    if (mounted) {
                      setState(() {
                        _discovered.remove(d.deviceId);
                        // 配对成功直接进入会话。
                        if (engine.peerById(d.deviceId) != null) {
                          _activeKey = d.deviceId;
                        }
                      });
                    }
                  },
                  child: const Text('配对'),
                ),
              );
            },
          ),
        ),
        if (discovered.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              _mcastOk
                  ? '正在搜索同一网络内未配对的设备…\n手机端:设备页下拉刷新即可被搜索到'
                  : '当前网络组播被禁,发现依赖子网扫描(可能较慢或不全)\n可在对端设备页输入本机 IP 手动添加',
              style:
                  TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
    final engine = this.engine;
    final img = e.isGroup
        ? Avatars.imageOf(engine, groupId: e.key)
        : Avatars.imageOf(engine, peerId: e.key);
    final Widget avatar = CircleAvatar(
      radius: 21,
      backgroundColor:
          e.isGroup ? scheme.primaryContainer : scheme.secondaryContainer,
      backgroundImage: img,
      child: img == null
          ? Icon(e.isGroup ? Icons.groups_outlined : Icons.smartphone,
              size: 20,
              color: e.isGroup
                  ? scheme.onPrimaryContainer
                  : scheme.onSecondaryContainer)
          : null,
    );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(L10n.t('chat.clearAll')),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmClear(e);
                },
              ),
              ListTile(
                leading: Icon(Icons.link_off_outlined,
                    color: Theme.of(context).colorScheme.error),
                title: Text(L10n.t('devices.unpair')),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmUnpair(e.key, e.title);
                },
              ),
            ],
          ),
        ),
      );
      return;
    }
    _popupMenu(e, position);
  }

  /// 解除配对确认(双端清除聊天记录与信任关系)。
  Future<void> _confirmUnpair(String peerId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('devices.unpair')),
        content: Text('与 $name 解除配对?双方设备将删除全部聊天记录与信任关系。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L10n.t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L10n.t('common.confirm'))),
        ],
      ),
    );
    if (ok != true) return;
    await engine.unpair(peerId);
    // 保留 _activeKey:右栏切到墓碑会话面板(解绑说明 + 删除入口),
    // 用户确认后自行关闭。
    if (mounted) setState(() {});
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
        if (!e.isGroup)
          PopupMenuItem(
              value: 'unpair', child: Text(L10n.t('devices.unpair'))),
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
        case 'unpair':
          _confirmUnpair(e.key, e.title);
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
              Icon(Icons.lock_outline,
                  size: 52, color: scheme.outline),
              const SizedBox(height: 10),
              Text(L10n.t('chat.e2eTitle'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(L10n.t('chat.selectPlaceholder'),
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    final key = _activeKey!;
    final g = engine.groupById(key);
    if (g != null && engine.peers.isNotEmpty) {
      // key:桌面三栏切换会话时同类型 widget 会复用旧 State
      //(标题 B、消息列表却是 A 的内容)——按会话 key 强制重建。
      return ChatPage(
        key: ValueKey('g:$key'),
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
        key: ValueKey('p:$key'),
        peer: peer,
        engine: engine,
        embedded: true,
        onClose: () => setState(() => _activeKey = null),
      );
    }
    // 墓碑会话(对端已解绑):不再返回空白面板(旧版右栏永久空白
    // 且无关闭按钮),给出解绑说明与"删除会话"入口。
    return _tombstonePane(key, scheme);
  }

  /// 墓碑会话面板:系统消息 + 删除会话。
  Widget _tombstonePane(String key, ColorScheme scheme) {
    final msgs = engine.loadMessages(key);
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _activeKey = null),
        ),
        title: const Text('已解除配对'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: msgs.length,
        itemBuilder: (ctx, i) => Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              msgs[i].kind == Message.kindSystem
                  ? msgs[i].text
                  : '(历史消息已删除)',
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除会话'),
            onPressed: () async {
              await engine.removeConversation(key);
              if (mounted) setState(() => _activeKey = null);
            },
          ),
        ),
      ),
    );
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
