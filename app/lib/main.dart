import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'call.dart';
import 'call_page.dart';
import 'chat_page.dart';
import 'device_info.dart';
import 'adaptive_shell.dart';
import 'avatar.dart';
import 'globals.dart';
import 'i18n.dart';
import 'group_create_page.dart';
import 'hotspot_page.dart';
import 'intro_page.dart';
import 'search_page.dart';
import 'push_wake.dart';
import 'quick_pair_page.dart';
import 'remote_pair_page.dart';
import 'settings_page.dart';
import 'share_handler.dart';
import 'theme/app_theme.dart';
import 'toast.dart';
import 'webrtc_link.dart';

/// 命令行参数(便于同机多实例测试):
///   littlelaw.exe --data-dir C:\tmp\ll2 --name 测试机2
String? _argDataDir;
String? _argDeviceName;

/// 全局引擎单例。
LittleLawEngine? _engine;



Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // 视频播放
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--data-dir') _argDataDir = args[i + 1];
    if (args[i] == '--name') _argDeviceName = args[i + 1];
  }
  await themeController.load();
  await L10n.load(); // 语言设置(跟随系统/中文/English)
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
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        theme: themeController.light(),
        darkTheme: themeController.dark(),
        themeMode: themeController.mode,
        locale: L10n.localeOf(context),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
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

  Future<void> _maybeShowIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('intro_done') == true) return;
      await prefs.setBool('intro_done', true);
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      if (!ctx.mounted) return;
      await Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => IntroPage(
          onDone: () => Navigator.of(ctx).pop(),
        ),
      ));
    } catch (_) {}
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
        rendezvousUrl: await SettingsPage.loadRendezvousUrl().then((raw) {
          if (raw.isEmpty) return RendezvousClient.defaultUrl; // 内置公共服务
          if (raw.toLowerCase() == 'off') return null; // 显式关闭
          return raw; // 自建地址
        }),
        upnpEnabled: await SettingsPage.loadUpnpEnabled(),
        encryptFilesAtRest: true, // 收件按设备分目录 + 落盘加密
      );
      final iceServers = await SettingsPage.loadIceServers();
      final rtc = WebRtcLinkManager(engine: engine, iceServers: iceServers)
        ..start();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        activeEngine = engine;
        rtcManager = rtc;
      });
      ShareHandler.attach(engine); // 系统分享面板接入
      PushWake.attach(engine); // FCM 离线推送唤醒(可选,无配置自动禁用)
      // 配对请求全局监听(移动/桌面壳都弹 PIN 核对窗)。
      _pairReqSub?.cancel();
      _pairReqSub = engine.pairRequests.listen(showPairRequestDialog);
      // 首次使用:展示引导(一次)。
      unawaited(_maybeShowIntro());
      final calls = CallManager(engine: engine, iceServers: iceServers)
        ..start();
      callManager = calls;
      // 来电自动弹通话页(全屏呼入界面)。
      calls.stateChanges.listen((s) {
        if (s.state == CallState.incoming) {
          final nav = navigatorKey.currentState;
          if (nav == null) return;
          nav.push(PageRouteBuilder(
            opaque: false,
            pageBuilder: (_, _, _) => CallPage(manager: calls),
            fullscreenDialog: true,
          ));
        }
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

// ---------------------------------------------------------------------------
// 全局配对流程(移动端/桌面端共用;经 navigatorKey 弹窗,任何壳下都能响应)
// ---------------------------------------------------------------------------

StreamSubscription<PairRequestEvent>? _pairReqSub;

/// 收到配对请求 → PIN 核对弹窗(BootPage 全局挂接,桌面壳也有响应)。
void showPairRequestDialog(PairRequestEvent event) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  final skin = themeController.skin;
  showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
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
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
            activeEngine?.respondPair(event.requestId, false);
            Navigator.of(dctx).pop();
          },
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: () {
            activeEngine?.respondPair(event.requestId, true);
            Navigator.of(dctx).pop();
          },
          child: const Text('PIN 一致,同意'),
        ),
      ],
    ),
  );
}

/// 主动向发现的设备发起配对(等待对方同意,显示本端 PIN)。
Future<void> startPairFlow(DiscoveredDevice device,
    {VoidCallback? onFinished}) async {
  final engine = activeEngine;
  final ctx = navigatorKey.currentContext;
  if (engine == null || ctx == null) return;
  final skin = themeController.skin;
  final pin = engine.pinFor(device.info.certFingerprint);
  var cancelled = false;
  showDialog<void>(
    context: ctx,
    barrierDismissible: true,
    builder: (dctx) => AlertDialog(
      title: Text('与 ${device.info.deviceName} 配对'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('等待对方同意…请核对 PIN:'),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
            Navigator.of(dctx).pop();
          },
          child: const Text('取消'),
        ),
      ],
    ),
  );
  final result = await engine.requestPair(device);
  final nav = navigatorKey.currentState;
  if (nav != null && nav.canPop()) {
    nav.pop(); // 关闭等待弹窗
  }
  if (cancelled) return;
  showToast(
    result.accepted
        ? '已与 ${device.info.deviceName} 完成配对'
        : '配对被拒绝: ${result.message}',
    type: result.accepted ? ToastType.success : ToastType.error,
  );
  onFinished?.call();
}

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
    // WebRTC 远程链路事件:建立后自动进入聊天页,断开/失败 toast。
    _rtcSub = rtcManager?.linkEvents.listen((e) {
      if (e.error != null) {
        showToast('远程应答处理失败: ${e.error}', type: ToastType.error);
        return;
      }
      final peer = _engine?.peerById(e.peerId);
      final name = peer?.deviceName ?? '对方设备';
      showToast(
        e.connected ? '远程链路已建立: $name' : '远程链路已断开: $name',
        type: e.connected ? ToastType.success : ToastType.info,
      );
      if (e.connected && peer != null) {
        // 回到主页并直接进入与该设备的聊天页。
        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.popUntil((route) => route.isFirst);
          nav.push(MaterialPageRoute(
            builder: (_) => ChatPage(peer: peer, engine: _engine!),
          ));
        }
      }
    });
  }

  @override
  void dispose() {
    _rtcSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端(宽屏):三栏外壳(图标栏 + 会话列表 + 聊天面板)。
    final desktop = (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux) &&
        MediaQuery.sizeOf(context).width >= 850;
    if (desktop) {
      return const AdaptiveHomeShell();
    }
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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.devices_outlined),
            selectedIcon: const Icon(Icons.devices),
            label: L10n.t('nav.devices'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.hub_outlined),
            selectedIcon: const Icon(Icons.hub),
            label: L10n.t('nav.connect'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: L10n.t('nav.settings'),
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
      if (e is GroupSynced) setState(() {}); // 群列表刷新(建群/改群扇出)
      if (e is ProfileUpdated) setState(() {}); // 对端头像/名称更新
    }));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ 配对

  // ------------------------------------------------------------ 配对

  Future<void> _startPair(DiscoveredDevice d) {
    return startPairFlow(d,
        onFinished: () => setState(() => _discovered.remove(d.deviceId)));
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final engine = _engine!;
    final peers = engine.peers;
    // 渲染时过滤:已配对设备不出现在附近列表(同意配对瞬间即消失)。
    _discovered.removeWhere((id, d) => engine.peerById(id) != null);
    final discovered = _discovered.values.toList();

    return Center(
      // 桌面宽屏下限制内容宽度并居中,避免横条拉伸。
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: RefreshIndicator(
          // 下拉刷新:立即重宣告 + 子网扫描,快速发现新设备。
          onRefresh: () async {
            await engine.discovery.rescan();
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            SliverToBoxAdapter(child: _header(engine)),
            if (peers.isNotEmpty) ...[
              const _SectionLabel(''),
              SliverList.builder(
                itemCount: peers.length,
                itemBuilder: (ctx, i) => _peerCard(engine, peers[i]),
              ),
            ],
            // 群聊
            const _SectionLabel(''),
            SliverList.builder(
              itemCount: engine.groups.length + 1,
              itemBuilder: (ctx, i) => i == engine.groups.length
                  ? _createGroupCard(engine)
                  : _groupCard(engine, engine.groups[i]),
            ),
            const _SectionLabel(''),
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
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: Colors.transparent,
                  backgroundImage: Avatars.imageOf(engine),
                  child: Avatars.imageOf(engine) == null
                      ? Icon(
                          Identity.platformName() == 'android' ||
                                  Identity.platformName() == 'ios'
                              ? Icons.smartphone
                              : Icons.computer_outlined,
                          color: Colors.white,
                          size: 24,
                        )
                      : null,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(L10n.t('header.onlineCount', {'n': online}),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => SearchPage(engine: _engine!))),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.search,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            L10n.t('header.tagline'),
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
    final scheme = Theme.of(context).colorScheme;
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
            child: CircleAvatar(
              backgroundColor: Colors.transparent,
              backgroundImage:
                  Avatars.imageOf(engine, peerId: peer.deviceId),
              child: Avatars.imageOf(engine, peerId: peer.deviceId) == null
                  ? Icon(isPhone ? Icons.smartphone : Icons.computer_outlined,
                      color: online ? Colors.green : Colors.grey, size: 22)
                  : null,
            ),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (engine.isSelfDevice(peer.deviceId))
                Tooltip(
                  message: '我的设备(消息全量镜像)',
                  child: Icon(Icons.devices_other,
                      size: 16, color: scheme.primary),
                ),
              IconButton(
                icon: Icon(
                  engine.isSelfDevice(peer.deviceId)
                      ? Icons.devices
                      : Icons.devices_other_outlined,
                  size: 20,
                  color: engine.isSelfDevice(peer.deviceId)
                      ? scheme.primary
                      : null,
                ),
                tooltip: engine.isSelfDevice(peer.deviceId)
                    ? '取消我的设备标记'
                    : '标记为我的设备(消息全量镜像)',
                onPressed: () {
                  final nowSelf = !engine.isSelfDevice(peer.deviceId);
                  engine.setSelfDevice(peer.deviceId, nowSelf);
                  setState(() {});
                  showToast(
                    nowSelf
                        ? '${peer.deviceName} 已标记为我的设备,消息将全量镜像'
                        : '已取消 ${peer.deviceName} 的我的设备标记',
                    type: ToastType.success,
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.link_off_outlined,
                    size: 20, color: scheme.error),
                tooltip: '解除配对(双端清除数据)',
                onPressed: () => _confirmUnpair(peer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createGroupCard(LittleLawEngine engine) {
    final skin = themeController.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: ListTile(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupCreatePage(engine: engine),
          )),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add, color: skin.primary, size: 22),
          ),
          title: Text(L10n.t('devices.newGroup'),
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('把多个已配对设备拉到一个会话',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ),
      ),
    );
  }

  Widget _groupCard(LittleLawEngine engine, Group group) {
    final onlineCount = group.memberIds
        .where((id) => id != engine.identity.deviceId && engine.isOnline(id))
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: ListTile(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatPage(
              peer: engine.peers.first,
              engine: engine,
              group: group,
            ),
          )),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: themeController.skin.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined, size: 22),
          ),
          title: Text(group.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${group.memberIds.length} 名成员 · $onlineCount 在线',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
            // 曾经配对过的设备(本地有头像缓存)直接显示头像。
            child: CircleAvatar(
              backgroundColor: Colors.transparent,
              backgroundImage:
                  Avatars.imageOf(_engine!, peerId: d.deviceId),
              child: Avatars.imageOf(_engine!, peerId: d.deviceId) == null
                  ? Icon(isPhone ? Icons.smartphone : Icons.computer_outlined,
                      color: skin.primary, size: 22)
                  : null,
            ),
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
// 连接页:三种连接方式(服务器设置在设置页)
// ---------------------------------------------------------------------------

class ConnectPage extends StatelessWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    final rtc = rtcManager;
    if (engine == null || rtc == null) {
      return const SizedBox.shrink();
    }
    final items = [
      _ConnectTile(
        icon: Icons.qr_code_2_outlined,
        title: L10n.t('connect.qr'),
        subtitle: L10n.t('connect.qrSub'),
        color: const Color(0xFF0EBB9C),
        onTap: (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => QuickPairPage(engine: engine),
        )),
      ),
      _ConnectTile(
        icon: Icons.wifi_tethering_outlined,
        title: L10n.t('connect.hotspot'),
        subtitle: L10n.t('connect.hotspotSub'),
        color: const Color(0xFFFF7A3D),
        onTap: (ctx) => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => const HotspotPage())),
      ),
      _ConnectTile(
        icon: Icons.travel_explore_outlined,
        title: L10n.t('connect.remote'),
        subtitle: L10n.t('connect.remoteSub'),
        color: const Color(0xFF4F7CFF),
        onTap: (ctx) => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => RemotePairPage(rtc: rtc))),
      ),
    ];
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 紧凑网格:手机 2 列 / 宽屏 3 列。
        final cols = constraints.maxWidth > 900 ? 3 : 2;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L10n.t('connect.title'),
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(L10n.t('connect.subtitle'),
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
                  mainAxisExtent: 110,
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

class _ConnectTile extends StatelessWidget {
  const _ConnectTile({
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
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => onTap(context),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 设置页:身份卡 + 服务器设置 + 语言 + 主题 + 关于
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
                  // 头像:点击设置(选择图片,自动缩放;同步给已配对设备)。
                  GestureDetector(
                    onTap: () async {
                      final bytes = await Avatars.pickResized();
                      if (bytes != null) {
                        await engine.setMyAvatar(bytes);
                        setState(() {});
                      }
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.22),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 2),
                        image: Avatars.imageOf(engine) != null
                            ? DecorationImage(
                                image: Avatars.imageOf(engine)!,
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: Avatars.imageOf(engine) == null
                          ? const Icon(Icons.person,
                              color: Colors.white, size: 28)
                          : null,
                    ),
                  ),
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
        // 服务器设置(中转 / STUN / TURN / 备份)
        Card(
          child: ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(L10n.t('connect.servers')),
            subtitle: Text(L10n.t('connect.serversSub'),
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsPage(rtc: rtcManager!),
            )),
          ),
        ),
        const SizedBox(height: 14),
        // 语言
        Card(
          child: ListTile(
            leading: const Icon(Icons.translate_outlined),
            title: Text(L10n.t('settings.lang')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(L10n.t('settings.lang')),
                children: [
                  for (final entry in const [
                    ('', null),
                    ('zh', '中文'),
                    ('en', 'English'),
                  ])
                    SimpleDialogOption(
                      onPressed: () async {
                        await L10n.set(entry.$1);
                        themeController.refresh(); // 触发全局重建
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(entry.$2 ?? L10n.t('settings.langSystem')),
                    ),
                ],
              ),
            ),
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
                leading: const Icon(Icons.school_outlined),
                title: Text(L10n.t('intro.replay')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => IntroPage(onDone: () => Navigator.of(context).pop()),
                )),
              ),
              const Divider(indent: 16, endIndent: 16),
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
                subtitle: const Text('v2.1.0 · NoServer 架构 · 协议 v1'),
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
