import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'i18n.dart';
import 'toast.dart';

/// 群资料页:成员列表、拉人、踢人、改群名、退群、解散。
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({super.key, required this.engine, required this.groupId});
  final LittleLawEngine engine;
  final String groupId;

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  @override
  void initState() {
    super.initState();
    widget.engine.events.listen((e) {
      if (e is GroupSynced && e.groupId == widget.groupId) {
        if (mounted) setState(() {});
      }
    });
  }

  LittleLawEngine get engine => widget.engine;

  Future<void> _rename() async {
    final group = engine.groupById(widget.groupId);
    if (group == null) return;
    final ctrl = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('group.rename')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      engine.renameGroup(widget.groupId, name);
      setState(() {});
    }
  }

  Future<void> _addMembers() async {
    final group = engine.groupById(widget.groupId);
    if (group == null) return;
    final selected = <String>{};
    final candidates =
        engine.peers.where((p) => !group.memberIds.contains(p.deviceId)).toList();
    if (candidates.isEmpty) {
      showToast('没有可添加的已配对设备', type: ToastType.info);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(L10n.t('group.addMembers')),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in candidates)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(p.deviceId),
                    onChanged: (v) => setInner(() =>
                        v == true ? selected.add(p.deviceId) : selected.remove(p.deviceId)),
                    title: Text(p.deviceName),
                    subtitle: Text(
                        p.deviceModel.isNotEmpty ? p.deviceModel : p.platform,
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('添加')),
          ],
        ),
      ),
    );
    if (ok == true && selected.isNotEmpty) {
      engine.addGroupMembers(widget.groupId, selected.toList());
      showToast('已添加 ${selected.length} 名成员', type: ToastType.success);
    }
  }

  Future<void> _confirm(String title, String body, VoidCallback onOk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) onOk();
  }

  @override
  Widget build(BuildContext context) {
    final group = engine.groupById(widget.groupId);
    if (group == null) {
      // 群已解散/被移出。
      return Scaffold(
        appBar: AppBar(title: const Text('群聊')),
        body: const Center(child: Text('该群已不存在')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('group.info'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.groups_outlined,
                        size: 30, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        Text('${group.memberIds.length} 名成员',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: L10n.t('group.rename'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _rename,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Text(L10n.t('devices.groups') == '群聊' ? '成员' : 'Members',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14))),
              TextButton.icon(
                onPressed: _addMembers,
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          for (final id in group.memberIds)
            _memberTile(group, id, scheme),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
            ),
            onPressed: () => _confirm('退出群聊', '退出后本机保留聊天记录,'
                    '重新入群前无法收发该群消息。', () {
              engine.leaveGroup(widget.groupId);
              Navigator.of(context).pop();
            }),
            icon: const Icon(Icons.logout_outlined),
            label: Text(L10n.t('group.leave')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
            ),
            onPressed: () => _confirm('解散群聊',
                '解散后全体成员的该群与群消息将被删除,且不可恢复。', () {
              engine.dissolveGroup(widget.groupId);
              Navigator.of(context).pop();
            }),
            icon: const Icon(Icons.delete_outline_outlined),
            label: Text(L10n.t('group.dissolve')),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(Group group, String memberId, ColorScheme scheme) {
    final isMe = memberId == engine.identity.deviceId;
    final peer = isMe ? null : engine.peerById(memberId);
    final name = isMe
        ? '${engine.identity.deviceName}(我)'
        : (peer?.deviceName ?? '未知设备');
    final subtitle = isMe
        ? engine.identity.deviceModel
        : (peer?.deviceModel.isNotEmpty == true
            ? peer!.deviceModel
            : (peer?.platform ?? ''));
    final online = isMe || engine.isOnline(memberId);
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: Icon(
          isMe
              ? Icons.person
              : (peer?.platform == 'android' || peer?.platform == 'ios'
                  ? Icons.smartphone
                  : Icons.computer_outlined),
          size: 20,
          color: scheme.onSecondaryContainer,
        ),
      ),
      title: Text(name),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? Colors.green : Colors.grey,
            ),
          ),
          if (!isMe)
            IconButton(
              tooltip: L10n.t('group.removeMember'),
              icon: const Icon(Icons.person_remove_outlined, size: 20),
              onPressed: () => _confirm('移出成员',
                  '将 $name 移出群聊?对方本地的群与消息会被删除。', () {
                engine.removeGroupMembers(widget.groupId, [memberId]);
              }),
            ),
        ],
      ),
    );
  }
}
