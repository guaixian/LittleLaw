import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 启动时加载持久化配置。
  static Future<List<String>> loadIceServers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyIceServers) ?? WebRtcLinkManager.defaultIceServers;
  }

  /// 启动时加载中转服务器地址(空 = 不启用,纯 NoServer 模式)。
  static Future<String> loadRendezvousUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRendezvousUrl) ?? '';
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
    widget.rtc.iceServers = servers;
    widget.rtc.configureTurn(
        username: _turnUserCtrl.text.trim().isEmpty ? null : _turnUserCtrl.text.trim(),
        credential:
            _turnPassCtrl.text.trim().isEmpty ? null : _turnPassCtrl.text.trim());
    showToast('已保存,中转服务器设置在下次启动生效', type: ToastType.success);
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
          const Text('配置后:重启自动重连远程设备、离线消息经服务器暂存送达。'
              '留空则纯 NoServer 模式,全部功能不受影响。',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _rendezvousCtrl,
            decoration: const InputDecoration(
              labelText: '服务器 WebSocket 地址',
              hintText: 'ws://你的服务器IP:47600/ws 或 wss://域名/ws',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
        ],
      ),
    );
  }
}
