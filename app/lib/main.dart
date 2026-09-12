import 'dart:async';

import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_page.dart';
import 'device_info.dart';
import 'hotspot_page.dart';
import 'quick_pair_page.dart';
import 'remote_pair_page.dart';
import 'settings_page.dart';
import 'theme/app_theme.dart';
import 'toast.dart';
import 'webrtc_link.dart';

/// 命令行参数(便于同机多实例测试):
///   littlelaw.exe --data-dir C:\tmp\ll2 --name 测试机2
String? _argDataDir;
String? _argDeviceName;

/// 全局引擎单例。
LittleLawEngine? _engine;

/// 全局 WebRTC 链路管理器。
WebRtcLinkManager? _rtc;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // 视频播放
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--data-dir') _argDataDir = args[i + 1];
    if (args[i] == '--name') _argDeviceName = args[i + 1];
  }
  await themeController.load();
  runApp(const LittleLawApp());
}

class LittleLawApp extends StatelessWidget {
  const LittleLawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'LittleLaw',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        theme: themeController.light(),
        darkTheme: themeController.dark(),
        themeMode: themeController.mode,
        home: const BootPage(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 启动页:初始化引擎
// ---------------------------------------------------------------------------

class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final dataDir =
          _argDataDir ?? (await getApplicationSupportDirectory()).path;
      // 机型采集(显示用);桌面端缺省名带计算机名,移动端由引擎按 "平台-型号" 生成。
      final model = await gatherDeviceModel();
      final defaultName = _argDeviceName ?? await gatherDesktopDefaultName();
      final engine = await LittleLawEngine.start(
        dataDir: dataDir,
        deviceName: defaultName,
        deviceModel: model,
      );
      final iceServers = await SettingsPage.loadIceServers();
      final rtc = WebRtcLinkManager(engine: engine, iceServers: iceServers)
        ..start();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _rtc = rtc;
      });
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = themeController.skin;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: skin.gradient),
        child: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('引擎启动失败:\n$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield_outlined,
                          size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    const Text('LittleLaw',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    const Text('端到端加密 · 设备直连',
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 28),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 主页骨架:底部导航 设备 / 连接 / 我的
// ---------------------------------------------------------------------------

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription? _rtcSub;

  @override
  void initState() {
    super.initState();
    // WebRTC 远程链路建立/断开 → 全局 toast。
    _rtcSub = _rtc?.linkEvents.listen((e) {
      final name = _engine?.peerById(e.peerId)?.deviceName ?? '对方设备';
      showToast(
        e.connected ? '远程链路已建立: $name' : '远程链路已断开: $name',
        type: e.connected ? ToastType.success : ToastType.info,
      );
    });
  }

  @override
  void dispose() {
    _rtcSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DevicesPage(),
      const ConnectPage(),
      const ProfilePage(),
    ];
    return Scaffold(
      // SafeArea 防止内容顶到状态栏(移动端)。
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: '连接',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 设备页:已配对 + 发现的设备
// ---------------------------------------------------------------------------

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _discovered = <String, DiscoveredDevice>{};
  final _subscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    final engine = _engine!;

    _subscriptions.add(engine.discoveredDevices.listen((d) {
      if (engine.peerById(d.deviceId) != null) return; // 已配对的不重复展示
      setState(() => _discovered[d.deviceId] = d);
    }));
    // 设备离开(报文超时):未配对的从发现列表移除;
    // 已配对的由引擎标记离线,经 PeerStatusChanged 刷新。
    _subscriptions.add(engine.discovery.expiredDevices.listen((deviceId) {
      if (_discovered.remove(deviceId) != null) setState(() {});
    }));
    _subscriptions.add(engine.events.listen((e) {
      if (e is PeerStatusChanged) setState(() {});
    }));
    _subscriptions.add(engine.pairRequests.listen(_showPairRequest));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ 配对

  void _showPairRequest(PairRequestEvent event) {
    final skin = themeController.skin;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('配对请求'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${event.requester.deviceName} (${event.requester.platform}) '
                '请求与本机配对'),
            const SizedBox(height: 20),
            const Text('与对方设备核对 PIN 码', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: skin.gradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                event.pin,
                style: const TextStyle(
                    fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),
            const Text('PIN 不一致说明链路可能被监听,请拒绝',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _engine!.respondPair(event.requestId, false);
              Navigator.of(ctx).pop();
            },
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () {
              _engine!.respondPair(event.requestId, true);
              Navigator.of(ctx).pop();
              setState(() {});
            },
            child: const Text('PIN 一致,同意'),
          ),
        ],
      ),
    );
  }

  Future<void> _startPair(DiscoveredDevice device) async {
    final engine = _engine!;
    final skin = themeController.skin;
    final pin = engine.pinFor(device.info.certFingerprint);
    var cancelled = false;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text('与 ${device.info.deviceName} 配对'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('等待对方同意…请核对 PIN:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: skin.gradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(pin,
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: Colors.white)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );
    final result = await engine.requestPair(device);
    if (!mounted || cancelled) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    showToast(
      result.accepted
          ? '已与 ${device.info.deviceName} 完成配对'
          : '配对被拒绝: ${result.message}',
      type: result.accepted ? ToastType.success : ToastType.error,
    );
    setState(() => _discovered.remove(device.deviceId));
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final engine = _engine!;
    final peers = engine.peers;
    final discovered = _discovered.values.toList();

    return Center(
      // 桌面宽屏下限制内容宽度并居中,避免横条拉伸。
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header(engine)),
            if (peers.isNotEmpty) ...[
              const _SectionLabel('已配对'),
              SliverList.builder(
                itemCount: peers.length,
                itemBuilder: (ctx, i) => _peerCard(engine, peers[i]),
              ),
            ],
            const _SectionLabel('附近的设备'),
            if (discovered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('正在搜索局域网设备…',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('确保对方设备已打开 LittleLaw 并接入同一网络',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: discovered.length,
                itemBuilder: (ctx, i) => _discoveredCard(discovered[i]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// 渐变头部:本机身份 + 状态。
  Widget _header(LittleLawEngine engine) {
    final skin = themeController.skin;
    final online = engine.peers.where((p) => engine.isOnline(p.deviceId)).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: skin.gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: skin.primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Identity.platformName() == 'android' ||
                          Identity.platformName() == 'ios'
                      ? Icons.smartphone
                      : Icons.computer_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(engine.identity.deviceName,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(
                      '${platformLabel(Identity.platformName())} · ${engine.identity.deviceModel} · 指纹 ${engine.identity.fingerprint.substring(0, 8)}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$online 台在线',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '局域网安全直连 · 消息只存两台设备',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _peerCard(LittleLawEngine engine, Peer peer) {
    final online = engine.isOnline(peer.deviceId);
    final isPhone = peer.platform == 'android' || peer.platform == 'ios';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: ListTile(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatPage(peer: peer, engine: engine),
          )),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (online ? Colors.green : Colors.grey)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(isPhone ? Icons.smartphone : Icons.computer_outlined,
                color: online ? Colors.green : Colors.grey, size: 22),
          ),
          title: Text(peer.deviceName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            peer.deviceModel.isNotEmpty
                ? '${platformLabel(peer.platform)} · ${peer.deviceModel} · ${online ? "在线" : "离线"}'
                : '${platformLabel(peer.platform)} · ${online ? "在线" : "离线"}',
            style: TextStyle(
                fontSize: 12,
                color: online ? Colors.green : Colors.grey.shade500),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.link_off_outlined, size: 20),
            tooltip: '解除配对(双端清除数据)',
            onPressed: () => _confirmUnpair(peer),
          ),
        ),
      ),
    );
  }

  Widget _discoveredCard(DiscoveredDevice d) {
    final skin = themeController.skin;
    final isPhone = d.info.platform == 'android' || d.info.platform == 'ios';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(isPhone ? Icons.smartphone : Icons.computer_outlined,
                color: skin.primary, size: 22),
          ),
          title: Text(d.info.deviceName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            d.info.deviceModel.isNotEmpty
                ? '${platformLabel(d.info.platform)} · ${d.info.deviceModel}'
                : '${platformLabel(d.info.platform)} · ${d.host}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          trailing: FilledButton.tonal(
            onPressed: () => _startPair(d),
            child: const Text('配对'),
          ),
        ),
      ),
    );
  }

  void _confirmUnpair(Peer peer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解除与 ${peer.deviceName} 的配对?'),
        content: const Text('双方将同时删除全部聊天记录与信任关系(Telegram 模式),不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _engine!.unpair(peer.deviceId);
              showToast('已解除与 ${peer.deviceName} 的配对', type: ToastType.success);
              setState(() {});
            },
            child: const Text('解除'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                letterSpacing: 1)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 连接页:四种连接方式
// ---------------------------------------------------------------------------

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _ConnectItem(
        icon: Icons.qr_code_2_outlined,
        title: '碰一碰 / 扫一扫',
        subtitle: '同局域网免 PIN 快速配对',
        color: const Color(0xFF0EBB9C),
        onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => QuickPairPage(engine: _engine!),
        )),
      ),
      _ConnectItem(
        icon: Icons.wifi_tethering_outlined,
        title: '热点直传',
        subtitle: '没有路由器时直连互传',
        color: const Color(0xFFFF7A3D),
        onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => const HotspotPage(),
        )),
      ),
      _ConnectItem(
        icon: Icons.travel_explore_outlined,
        title: '远程连接',
        subtitle: '不在同一网络?WebRTC 跨网互联',
        color: const Color(0xFF4F7CFF),
        onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => RemotePairPage(rtc: _rtc!),
        )),
      ),
      _ConnectItem(
        icon: Icons.tune_outlined,
        title: '连接设置',
        subtitle: 'STUN / TURN 服务器配置',
        color: const Color(0xFF8B5CF6),
        onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => SettingsPage(rtc: _rtc!),
        )),
      ),
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 响应式列数:手机单列 / 平板双列 / 桌面四列。
        final w = constraints.maxWidth;
        final cols = w > 1100 ? 4 : w > 700 ? 2 : 1;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('连接方式',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('根据所处的网络环境选择',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: 132,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: items.length,
                itemBuilder: (ctx, i) => items[i],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConnectItem extends StatelessWidget {
  const _ConnectItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final void Function(BuildContext) onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => onTap(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 我的页:身份卡 + 主题 + 关于
// ---------------------------------------------------------------------------

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final engine = _engine!;
    final skin = themeController.skin;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 身份卡
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: skin.gradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fingerprint, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(engine.identity.deviceName,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text(
                          '${platformLabel(Identity.platformName())} · ${engine.identity.deviceModel}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                        Text('端口 ${engine.grpcPort}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white60)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '修改设备名',
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white, size: 20),
                    onPressed: () => _rename(engine),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('设备 ID',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7))),
              SelectableText(engine.identity.deviceId,
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
              const SizedBox(height: 8),
              Text('证书指纹',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7))),
              SelectableText(engine.identity.fingerprint,
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 主题皮肤
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('主题皮肤',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final s in Skins.all) _skinDot(s),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('跟随系统'),
                        icon: Icon(Icons.settings_suggest_outlined, size: 16)),
                    ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('浅色'),
                        icon: Icon(Icons.light_mode_outlined, size: 16)),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('深色'),
                        icon: Icon(Icons.dark_mode_outlined, size: 16)),
                  ],
                  selected: {themeController.mode},
                  onSelectionChanged: (s) {
                    themeController.setMode(s.first);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // 关于
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('加密与安全'),
                subtitle: const Text('TLS 1.3 · 证书指纹绑定 · 配对令牌'),
                onTap: () {},
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于 LittleLaw'),
                subtitle: const Text('NoServer 架构 · 协议 v1'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skinDot(Skin s) {
    final selected = themeController.skin.id == s.id;
    return GestureDetector(
      onTap: () {
        themeController.setSkin(s);
        setState(() {});
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: s.gradient,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: s.primary, width: 3)
                  : Border.all(color: Colors.transparent, width: 3),
              boxShadow: selected
                  ? [BoxShadow(color: s.primary.withValues(alpha: 0.4), blurRadius: 8)]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
          const SizedBox(height: 5),
          Text(s.name,
              style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? s.primary
                      : Colors.grey.shade600,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
    );
  }

  Future<void> _rename(LittleLawEngine engine) async {
    final ctrl = TextEditingController(text: engine.identity.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改设备名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新设备名'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await engine.renameDevice(name);
      setState(() {});
    }
  }
}
