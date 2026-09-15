import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'hotspot.dart';
import 'toast.dart';

/// 热点直传页:无共同路由器(户外/会议室)时,一台设备开热点,
/// 另一台加入,加入后即处于同一局域网,现有引擎自动接管
/// (发现/配对/聊天/传输逻辑零改动)。
class HotspotPage extends StatefulWidget {
  const HotspotPage({super.key});

  @override
  State<HotspotPage> createState() => _HotspotPageState();
}

class _HotspotPageState extends State<HotspotPage> {
  HotspotInfo? _hotspot;
  String _status = '';
  bool _busy = false;
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String s) => setState(() => _status = s);

  Future<void> _createHotspot() async {
    setState(() => _busy = true);
    try {
      // LocalOnlyHotspot 需要定位权限(Android 13+ 用附近设备权限)。
      final loc = await Permission.location.request();
      final nearby = await Permission.nearbyWifiDevices.request();
      // 权限对话框期间用户可能已退出页面:每个 await 后判 mounted,
      // 否则 setState() called after dispose() 崩溃。
      if (!mounted) return;
      if (!loc.isGranted && !nearby.isGranted) {
        _setStatus('需要定位或附近设备权限才能创建热点');
        return;
      }
      final info = await HotspotManager.startHotspot();
      if (!mounted) return;
      setState(() {
        _hotspot = info;
        _status = '热点已开启。另一台设备扫码或手动加入后,回到主页即可互相发现';
      });
      showToast('热点已开启: ${info.ssid}', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      _setStatus('创建热点失败: $e');
      showToast('创建热点失败: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinHotspot() async {
    if (_ssidCtrl.text.isEmpty) {
      _setStatus('请输入热点名称(SSID)');
      return;
    }
    setState(() => _busy = true);
    try {
      await HotspotManager.joinHotspot(_ssidCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;
      _setStatus('已加入热点,引擎流量已切换到该网络,回到主页等待发现对方');
      showToast('已加入热点', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      _setStatus('加入失败: $e(也可以去系统 WiFi 设置手动加入)');
      showToast('加入热点失败', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final programmatic = HotspotManager.isProgrammaticSupported;
    return Scaffold(
      appBar: AppBar(title: const Text('热点直传(无路由器场景)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: const Text('原理'),
              subtitle: Text(Platform.isAndroid || Platform.isIOS
                  ? '一台设备开热点,另一台加入 → 同一局域网 → 引擎自动接管。'
                    '热点仅组局域网,不消耗任何流量。'
                  : '任一台设备用系统功能开热点,另一台加入即可。'
                    '桌面端请使用系统设置中的热点/网络共享功能。'),
            ),
          ),
          const SizedBox(height: 16),
          if (programmatic) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _createHotspot,
              icon: const Icon(Icons.router),
              label: const Text('创建热点(本机当主机)'),
            ),
            if (_hotspot != null) ...[
              const SizedBox(height: 16),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: _hotspot!.wifiQr,
                    size: 220,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: SelectableText(
                  'SSID: ${_hotspot!.ssid}\n密码: ${_hotspot!.password}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    try {
                      await HotspotManager.stopHotspot();
                    } catch (e) {
                      if (mounted) {
                        showToast('关闭热点失败: $e', type: ToastType.error);
                      }
                    }
                    if (mounted) setState(() => _hotspot = null);
                  },
                  child: const Text('关闭热点'),
                ),
              ),
            ],
            const Divider(height: 32),
            const Text('加入对方热点(Android 10+):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _ssidCtrl,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: 'SSID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: '密码'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _joinHotspot,
              child: const Text('加入热点'),
            ),
          ] else if (Platform.isIOS) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.phone_iphone),
                title: Text('iOS 操作指引'),
                subtitle: Text('设置 → 个人热点 → 允许其他人加入;\n'
                    '另一台设备加入该热点后,回到 LittleLaw 主页即可。\n'
                    '(iOS 不允许应用程序化创建热点,为系统限制)'),
              ),
            ),
          ] else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.computer),
                title: const Text('桌面端操作指引'),
                subtitle: Text(Platform.isWindows
                    ? '设置 → 网络和 Internet → 移动热点 → 开启;\n另一台设备加入后回到本页应用即可。'
                    : Platform.isMacOS
                        ? '系统设置 → 通用 → 共享 → 互联网共享 → 开启;\n另一台设备加入后回到本应用即可。'
                        : '使用 nmcli 创建热点:\nnmcli dev wifi hotspot ifname wlan0 ssid LittleLaw password "12345678"'),
              ),
            ),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
        ],
      ),
    );
  }
}
