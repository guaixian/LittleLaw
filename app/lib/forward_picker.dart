import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'avatar.dart';
import 'chat_page.dart';
import 'globals.dart';
import 'i18n.dart';
import 'toast.dart';

/// 转发选择器:把内容(text / 文件,可多个)发到某个会话(1:1 或群)。
/// 供消息长按"转发"与系统分享入口共用(微信/飞书式会话选择面板)。
Future<void> showForwardPicker(
  LittleLawEngine engine, {
  String? text,
  List<String>? filePaths,
  String? filePath,
}) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return Future.value();
  final files = [
    ?filePath,
    ...?filePaths,
  ];
  return showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Theme.of(ctx).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scrollController) => _ForwardSheet(
        engine: engine,
        text: text,
        filePaths: files.isEmpty ? null : files,
        controller: scrollController,
        onClose: () => Navigator.of(sheetCtx).pop(),
      ),
    ),
  );
}

class _ForwardSheet extends StatelessWidget {
  const _ForwardSheet({
    required this.engine,
    required this.controller,
    required this.onClose,
    this.text,
    this.filePaths,
  });

  final LittleLawEngine engine;
  final ScrollController controller;
  final VoidCallback onClose;
  final String? text;
  final List<String>? filePaths;

  Future<void> _sendTo(String target, {required bool isGroup}) async {
    onClose();
    try {
      if (text != null) {
        isGroup
            ? await engine.sendGroupText(target, text!)
            : await engine.sendText(target, text!);
      }
      for (final path in filePaths ?? const <String>[]) {
        isGroup
            ? await engine.sendGroupFile(target, path)
            : await engine.sendFile(target, path);
      }
      final name = isGroup
          ? engine.groupById(target)?.name
          : engine.peerById(target)?.deviceName;
      showToast('已发送到 $name', type: ToastType.success);
      // 发送后直达目标会话。
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.popUntil((route) => route.isFirst);
        if (isGroup) {
          final group = engine.groupById(target);
          if (group != null && engine.peers.isNotEmpty) {
            nav.push(MaterialPageRoute(
              builder: (_) => ChatPage(
                  peer: engine.peers.first, engine: engine, group: group),
            ));
          }
        } else {
          final peer = engine.peerById(target);
          if (peer != null) {
            nav.push(MaterialPageRoute(
              builder: (_) => ChatPage(peer: peer, engine: engine),
            ));
          }
        }
      }
    } catch (e) {
      showToast('发送失败: $e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peers = engine.peers;
    final groups = engine.groups;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(L10n.t('forward.title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        for (final g in groups)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              backgroundImage:
                  Avatars.imageOf(engine, groupId: g.id),
              child: Avatars.imageOf(engine, groupId: g.id) == null
                  ? Icon(Icons.groups_outlined,
                      size: 20, color: scheme.onPrimaryContainer)
                  : null,
            ),
            title: Text(g.name),
            subtitle: Text(L10n.t('devices.groupMembers', {'n': g.memberIds.length}),
                style: const TextStyle(fontSize: 12)),
            onTap: () => _sendTo(g.id, isGroup: true),
          ),
        for (final p in peers)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              backgroundImage:
                  Avatars.imageOf(engine, peerId: p.deviceId),
              child: Avatars.imageOf(engine, peerId: p.deviceId) == null
                  ? Icon(
                      p.platform == 'android' || p.platform == 'ios'
                          ? Icons.smartphone
                          : Icons.computer_outlined,
                      size: 20,
                      color: scheme.onSecondaryContainer,
                    )
                  : null,
            ),
            title: Text(p.deviceName),
            subtitle: Text(
                p.deviceModel.isNotEmpty ? p.deviceModel : p.platform,
                style: const TextStyle(fontSize: 12)),
            onTap: () => _sendTo(p.deviceId, isGroup: false),
          ),
        if (peers.isEmpty && groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(L10n.t('forward.empty'))),
          ),
      ],
    );
  }
}
