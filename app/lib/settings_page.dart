import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webrtc_link.dart';

/// 设置页:WebRTC ICE 服务器(STUN/TURN)配置。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.rtc});
  final WebRtcLinkManager rtc;

  static const _keyIceServers = 'ice_servers';
  static const _keyTurnUsername = 'turn_username';
  static const _keyTurnCredential = 'turn_credential';

  /// 启动时加载持久化配置。
  static Future<List<String>> loadIceServers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyIceServers) ?? WebRtcLinkManager.defaultIceServers;
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _iceCtrl;
  final _turnUserCtrl = TextEditingController();
  final _turnPassCtrl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final servers = prefs.getStringList(SettingsPage._keyIceServers) ??
        WebRtcLinkManager.defaultIceServers;
    _iceCtrl = TextEditingController(text: servers.join('\n'));
    _turnUserCtrl.text = prefs.getString(SettingsPage._keyTurnUsername) ?? '';
    _turnPassCtrl.text = prefs.getString(SettingsPage._keyTurnCredential) ?? '';
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final servers = _iceCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (servers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少保留一个 STUN 服务器')));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(SettingsPage._keyIceServers, servers);
    await prefs.setString(SettingsPage._keyTurnUsername, _turnUserCtrl.text.trim());
    await prefs.setString(
        SettingsPage._keyTurnCredential, _turnPassCtrl.text.trim());
    widget.rtc.iceServers = servers;
    widget.rtc.configureTurn(
        username: _turnUserCtrl.text.trim().isEmpty ? null : _turnUserCtrl.text.trim(),
        credential:
            _turnPassCtrl.text.trim().isEmpty ? null : _turnPassCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存,下次建连生效')));
    }
  }

  @override
  void dispose() {
    if (_loaded) _iceCtrl.dispose();
    _turnUserCtrl.dispose();
    _turnPassCtrl.dispose();
    super.dispose();
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
        ],
      ),
    );
  }
}
