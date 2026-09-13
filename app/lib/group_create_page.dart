import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'chat_page.dart';
import 'toast.dart';

/// 新建群聊:群名 + 从已配对设备多选成员。
class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key, required this.engine});
  final LittleLawEngine engine;

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _nameCtrl = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast('请输入群名', type: ToastType.error);
      return;
    }
    if (_selected.isEmpty) {
      showToast('请至少选择一名成员', type: ToastType.error);
      return;
    }
    final group = widget.engine.createGroup(name, _selected.toList());
    showToast('群「$name」已创建', type: ToastType.success);
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatPage(
        peer: widget.engine.peers.first,
        engine: widget.engine,
        group: group,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final peers = widget.engine.peers;
    return Scaffold(
      appBar: AppBar(title: const Text('新建群聊')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '群名称'),
          ),
          const SizedBox(height: 16),
          Text('选择成员(${_selected.length}/${peers.length})',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          for (final p in peers)
            CheckboxListTile(
              value: _selected.contains(p.deviceId),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(p.deviceId);
                } else {
                  _selected.remove(p.deviceId);
                }
              }),
              title: Text(p.deviceName),
              subtitle: Text(
                p.deviceModel.isNotEmpty ? p.deviceModel : p.platform,
                style: const TextStyle(fontSize: 12),
              ),
              secondary: Icon(
                p.platform == 'android' || p.platform == 'ios'
                    ? Icons.smartphone
                    : Icons.computer_outlined,
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('创建群聊'),
          ),
        ],
      ),
    );
  }
}
