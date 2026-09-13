import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup.dart';
import 'toast.dart';
import 'webrtc_link.dart';

/// 设置页:WebRTC ICE 服务器(STUN/TURN)配置。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.rtc});
  final WebRtcLinkManager rtc;

  static const _keyIceServers = 'ice_servers';
  static const _keyTurnUsername = 'turn_username';
  static const _keyTurnCredential = 'turn_credential';
  static const _keyRendezvousUrl = 'rendezvous_url';
  static const _keyUpnpEnabled = 'upnp_enabled';

  /// 启动时加载持久化配置。
  static Future<List<String>> loadIceServers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyIceServers) ?? WebRtcLinkManager.defaultIceServers;
  }

  /// 启动时加载中转服务器地址(空 = 内置公共服务)。
  static Future<String> loadRendezvousUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRendezvousUrl) ?? '';
  }

  /// UPnP 端口映射开关(默认关,隐私自决)。
  static Future<bool> loadUpnpEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUpnpEnabled) ?? false;
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _iceCtrl;
  final _turnUserCtrl = TextEditingController();
  final _turnPassCtrl = TextEditingController();
  final _rendezvousCtrl = TextEditingController();
  bool _loaded = false;
  bool _rcConnected = false;
  bool _upnpEnabled = false;
  StreamSubscription? _rcSub;

  @override
  void initState() {
    super.initState();
    _load();
    // 中转服务器连接状态指示。
    final rc = widget.rtc.engine.rendezvous;
    _rcConnected = rc?.connected ?? false;
    _rcSub = rc?.connectionState.listen((up) {
      if (mounted) setState(() => _rcConnected = up);
    });
  }

  @override
  void dispose() {
    _rcSub?.cancel();
    if (_loaded) _iceCtrl.dispose();
    _turnUserCtrl.dispose();
    _turnPassCtrl.dispose();
    _rendezvousCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final servers = prefs.getStringList(SettingsPage._keyIceServers) ??
        WebRtcLinkManager.defaultIceServers;
    _iceCtrl = TextEditingController(text: servers.join('\n'));
    _turnUserCtrl.text = prefs.getString(SettingsPage._keyTurnUsername) ?? '';
    _turnPassCtrl.text = prefs.getString(SettingsPage._keyTurnCredential) ?? '';
    _rendezvousCtrl.text = prefs.getString(SettingsPage._keyRendezvousUrl) ?? '';
    _upnpEnabled = prefs.getBool(SettingsPage._keyUpnpEnabled) ?? false;
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final servers = _iceCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (servers.isEmpty) {
      showToast('至少保留一个 STUN 服务器', type: ToastType.error);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(SettingsPage._keyIceServers, servers);
    await prefs.setString(SettingsPage._keyTurnUsername, _turnUserCtrl.text.trim());
    await prefs.setString(
        SettingsPage._keyTurnCredential, _turnPassCtrl.text.trim());
    await prefs.setString(
        SettingsPage._keyRendezvousUrl, _rendezvousCtrl.text.trim());
    await prefs.setBool(SettingsPage._keyUpnpEnabled, _upnpEnabled);
    widget.rtc.iceServers = servers;
    widget.rtc.configureTurn(
        username: _turnUserCtrl.text.trim().isEmpty ? null : _turnUserCtrl.text.trim(),
        credential:
            _turnPassCtrl.text.trim().isEmpty ? null : _turnPassCtrl.text.trim());
    showToast('已保存,中转服务器与 UPnP 设置在下次启动生效', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 中转服务器
          Row(
            children: [
              const Text('中转服务器(可选)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _rcConnected ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 4),
              Text(_rcConnected ? '已连接' : '未连接',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('配置后:重启自动重连远程设备、离线消息经服务器暂存送达、'
              '远程配对一扫即成。留空 = 内置公共服务 littlelaw.joywiki.cc;'
              '填 off = 关闭(纯 NoServer);或填自建地址。',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _rendezvousCtrl,
            decoration: const InputDecoration(
              labelText: '服务器 WebSocket 地址',
              hintText: '留空默认 wss://littlelaw.joywiki.cc/ws',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('UPnP 端口映射'),
            subtitle: const Text(
                '在家庭路由器上映射端口,获得公网直连端点(与 WebRTC 竞速建连)。'
                '会向中转服务器公布当前公网 IP:端口,内容仍全程加密。默认关闭。'),
            value: _upnpEnabled,
            onChanged: (v) => setState(() => _upnpEnabled = v),
          ),
          const SizedBox(height: 20),
          const Text('STUN 服务器(每行一个)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('用于跨互联网打洞时获取本机公网地址。无状态"照妖镜"服务,'
              '不经手任何数据。', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _iceCtrl,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'stun:stun.l.google.com:19302',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text('TURN 中继(可选)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('运营商 CGNAT 下打洞失败时的兜底中继。在上面的服务器列表加一行\n'
              'turn:你的服务器:3478,并在此填用户名/密码。',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _turnUserCtrl,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'TURN 用户名'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _turnPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'TURN 密码'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(height: 28),
          const Text('备份与恢复',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('把设备身份、全部配对与聊天记录打成加密包(AES-256-GCM,'
              '口令派生密钥)。恢复到新设备后沿用原身份,好友无需重新配对。',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('创建备份'),
                  onPressed: _createBackup,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('恢复备份'),
                  onPressed: _restoreBackup,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 备份 / 恢复

  Future<void> _createBackup() async {
    final pass = await _askPassphrase(confirm: true);
    if (pass == null || pass.isEmpty) return;
    try {
      await BackupManager(widget.rtc.engine).createBackup(pass);
    } catch (e) {
      showToast('备份失败: $e', type: ToastType.error);
    }
  }

  Future<void> _restoreBackup() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    final path = files.single.path;
    if (path == null || !mounted) return;
    final pass = await _askPassphrase(confirm: false);
    if (pass == null || pass.isEmpty || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复?'),
        content: const Text('当前设备上的身份、配对与聊天记录将被备份内容'
            '完全覆盖,恢复完成后应用将退出,重新打开即生效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖恢复')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final restored =
          await BackupManager(widget.rtc.engine).restoreBackup(path, pass);
      if (restored) {
        showToast('恢复完成,应用即将退出', type: ToastType.success);
        await Future<void>.delayed(const Duration(seconds: 2));
        exit(0);
      }
    } catch (e) {
      // 解密失败(口令错/文件坏)在这里兜底。
      showToast('恢复失败: $e', type: ToastType.error);
    }
  }

  /// 口令输入对话框。[confirm] = true 时二次确认。
  Future<String?> _askPassphrase({required bool confirm}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirm ? '设置备份口令' : '输入备份口令'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: '口令(至少 6 个字符)'),
            ),
            if (confirm)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('口令丢失将无法恢复备份,请务必牢记。',
                    style: TextStyle(fontSize: 12, color: Colors.red)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确定')),
        ],
      ),
    );
  }
}
