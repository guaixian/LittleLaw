import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';

import '../generated/littlelaw.pb.dart' as pb;
import '../identity/identity.dart';
import '../util.dart';

/// 发现到的局域网设备。
class DiscoveredDevice {
  DiscoveredDevice({
    required this.info,
    required this.host,
    required this.port,
    required this.lastSeenMs,
  });

  final pb.DeviceInfo info;
  final String host;
  final int port;
  int lastSeenMs;

  String get deviceId => info.deviceId;
}

/// 设备发现服务:UDP 组播为主,子网扫描兜底。
///
/// 报文 = protobuf 序列化的 DiscoveryPacket,带 magic 指纹与协议版本,
/// 不匹配的一律丢弃。收到陌生设备的报文会立即单播回执,使扫描方
/// 也能看到被扫描方(双向可见)。
class DiscoveryService {
  DiscoveryService({
    required this.identity,
    required this.grpcPort,
    this.discoveryPort = defaultDiscoveryPort,
    this.multicastGroup = defaultMulticastGroup,
    this.announceInterval = const Duration(seconds: 3),
    this.scanInterval = const Duration(seconds: 15),
    this.extraTargets = const [],
    this.includeLoopbackScan = false,
  });

  /// 固定协议常量。
  static const defaultDiscoveryPort = 47521;
  static const defaultMulticastGroup = '239.255.42.99';
  static const magic = 0x4C4C4157; // "LLAW"
  /// v2:宣告报文必须携带证书 DER + ECDSA 签名,且时间戳新鲜(±30s)。
  /// v1(明文无签名)已弃用:可伪造、可重放。
  static const protocolVersion = '2';

  /// 宣告报文时间窗:超出即视为重放,丢弃。
  static const _freshnessMs = 30 * 1000;

  final Identity identity;
  final int grpcPort;
  final int discoveryPort;
  final String multicastGroup;
  final Duration announceInterval;
  final Duration scanInterval;

  /// 额外发现目标(host:port 字符串),用于手动添加与同机测试。
  final List<String> extraTargets;

  /// 是否扫描 127.0.0.1(测试用)。
  final bool includeLoopbackScan;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  Timer? _announceTimer;
  Timer? _scanTimer;
  Timer? _expiryTimer;
  Timer? _netWatchTimer;

  /// 最近一次收到任何合法发现报文的时刻(接收看门狗依据)。
  int _lastRecvAnyMs = 0;

  /// 组播是否加入成功(false = 当前网络组播被禁,发现依赖子网扫描)。
  bool multicastJoined = false;

  /// 组播状态变化事件(UI 提示"当前网络组播被禁"用)。
  Stream<bool> get multicastHealth => _mcastHealth.stream;
  final _mcastHealth = StreamController<bool>.broadcast();

  /// 接收看门狗的"应有流量"判定(引擎注入:存在已配对设备时,静默
  /// 90s 属异常;一台孤立设备长期静默是正常的,不该反复重建 socket)。
  bool Function()? expectTraffic;

  final _devices = <String, DiscoveredDevice>{};
  final _replyCache = <String, int>{};
  final _controller = StreamController<DiscoveredDevice>.broadcast();
  final _expiredController = StreamController<String>.broadcast();

  /// 设备出现/刷新事件。
  Stream<DiscoveredDevice> get devices => _controller.stream;

  /// 设备消失事件(连续超时未收到其报文,判定为离开局域网)。
  /// 携带 deviceId。UI 应从发现列表移除;引擎应将对应设备标记离线。
  Stream<String> get expiredDevices => _expiredController.stream;

  /// 当前在线设备快照。
  List<DiscoveredDevice> get current => _devices.values.toList(growable: false);

  bool _started = false;
  bool _rebinding = false;
  String _bindSignature = '';

  /// 当前 IPv4 网卡签名(WiFi 漫游/DHCP 变化 → 签名变化 → 重建 socket)。
  Future<String> _currentSignature() async {
    final addrs = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false)) {
        for (final a in iface.addresses) {
          if (!a.isLoopback) addrs.add(a.address);
        }
      }
    } catch (_) {}
    addrs.sort();
    return addrs.join(',');
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _bindSocket();
    _lastRecvAnyMs = DateTime.now().millisecondsSinceEpoch;

    // 固定 3s 宣告(不做空闲退避:曾实测长时间空闲后互发现退化,
    // 可靠性优先;移动端耗电优化改由平台侧处理)。
    _announceTimer =
        Timer.periodic(announceInterval, (_) => unawaited(_announce()));
    _scanTimer = Timer.periodic(scanInterval, (_) => unawaited(_scanSubnet()));
    // 过期检测频率 = 宣告间隔,保证离线判定延迟稳定在 TTL±interval。
    _expiryTimer = Timer.periodic(announceInterval, (_) => _expireStale());
    // 网卡监测 + 接收看门狗:漫游/换网后组播成员资格失效要重建 socket;
    // 长时间收不到【任何】报文说明 socket 已聋(驱动/组播状态丢失等,
    // 重启 App 才能恢复的那类故障),主动重建 socket 自愈。
    _netWatchTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_checkNetworkChanged());
      _watchdogSweep();
    });

    await _announce();
  }

  /// 接收看门狗:已运行且"应有流量"(有已配对设备),但 90s 内一个包
  /// 都没收到——正常网络里配对设备的宣告/回复远比这密集,判定 socket
  /// 已聋(驱动/组播状态丢失等"重启 App 才能恢复"类故障),
  /// 主动重建 socket 自愈。
  void _watchdogSweep() {
    if (!_started || _rebinding) return;
    if (_lastRecvAnyMs <= 0) return;
    if (!(expectTraffic?.call() ?? true)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRecvAnyMs > 90 * 1000) {
      _lastRecvAnyMs = now; // 防止重建期间重复触发
      unawaited(_rebindSocket());
    }
  }

  Future<void> _checkNetworkChanged() async {
    if (!_started || _rebinding) return;
    final sig = await _currentSignature();
    if (sig != _bindSignature && _bindSignature.isNotEmpty) {
      await _rebindSocket();
    }
  }

  Future<void> _bindSocket() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    socket.broadcastEnabled = true;
    var joined = true;
    try {
      socket.joinMulticast(InternetAddress(multicastGroup));
    } catch (_) {
      // 某些平台/网卡不支持组播,降级为广播+扫描,不致命;
      // 状态上报给 UI 提示("当前网络组播被禁,发现依赖子网扫描")。
      joined = false;
    }
    if (joined != multicastJoined) {
      multicastJoined = joined;
      if (!_mcastHealth.isClosed) _mcastHealth.add(joined);
    }
    // Windows:子网扫描探测到不可达地址会触发 ICMP,让 receive() 抛
    // ConnectionReset;异常未接住会杀死监听订阅,发现从此失聪(重启才恢复)。
    // 这里全部兜住,出错即重建 socket 自愈。
    _socketSub = socket.listen(
      _onSocketEvent,
      onError: (_) => unawaited(_rebindSocket()),
      onDone: () => unawaited(_rebindSocket()),
    );
    _bindSignature = await _currentSignature();
  }

  Future<void> _rebindSocket() async {
    if (!_started || _rebinding) return;
    _rebinding = true;
    try {
      await _socketSub?.cancel();
      _socketSub = null;
      _socket?.close();
      _socket = null;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _bindSocket();
      await _announce(); // 重建后立即宣告
    } catch (_) {
      // 再失败:5s 后重试。
      Future.delayed(const Duration(seconds: 5), () {
        _rebinding = false;
        unawaited(_rebindSocket());
      });
      return;
    }
    _rebinding = false;
  }

  /// 手动重扫(下拉刷新触发):立即宣告一次 + 子网扫描。
  Future<void> rescan() async {
    if (!_started) return;
    await _announce();
    unawaited(_scanSubnet());
  }

  Future<void> stop() async {
    _started = false;
    _announceTimer?.cancel();
    _scanTimer?.cancel();
    _expiryTimer?.cancel();
    _netWatchTimer?.cancel();
    _lastRecvAnyMs = 0;
    // 先停订阅再关 socket,防止在途报文写入已关闭的流。
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    _rebinding = false;
    _devices.clear();
    _replyCache.clear();
    // 控制器保留,stop 后可重新 start。
  }

  /// 彻底销毁(不可再 start)。引擎退出时调用。
  Future<void> dispose() async {
    await stop();
    if (!_expiredController.isClosed) await _expiredController.close();
    if (!_controller.isClosed) await _controller.close();
    if (!_mcastHealth.isClosed) await _mcastHealth.close();
  }

  // ------------------------------------------------------------ 发送

  Uint8List _buildPacket() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // 精简披露:宣告只带配对必需字段。platform/deviceModel 属于隐私元数据,
    // 仅在配对(经 TLS 的 requestPair)或已成为可信设备后交换。
    final device = pb.DeviceInfo(
      deviceId: identity.deviceId,
      deviceName: identity.deviceName,
      platform: '',
      certFingerprint: identity.fingerprint,
      port: grpcPort,
      protocolVersion: protocolVersion,
      deviceModel: '',
    );
    final packet = pb.DiscoveryPacket(
      magic: magic,
      timestampMs: Int64(ts),
      device: device,
      certDer: Uint8List.fromList(Identity.derOfCertPem(identity.certPem)),
      // 签名覆盖 timestamp + 全部 DeviceInfo:改任何字段即失效。
      signature: identity
          .signMessage(_announceMessage(ts, device.writeToBuffer())),
    );
    return packet.writeToBuffer();
  }

  /// 验签摘要输入:8 字节大端时间戳 + DeviceInfo 序列化。
  static List<int> _announceMessage(int tsMs, List<int> deviceBytes) {
    final ts8 = Uint8List(8);
    ByteData.view(ts8.buffer).setInt64(0, tsMs, Endian.big);
    return [...ts8, ...deviceBytes];
  }

  Future<void> _announce() async {
    final socket = _socket;
    if (socket == null) return;
    final data = _buildPacket();

    // 1) 组播
    try {
      socket.send(data, InternetAddress(multicastGroup), discoveryPort);
    } catch (_) {}

    // 2) 定向广播(路由器不转发组播时兜底)
    for (final bcast in await _broadcastAddresses()) {
      try {
        socket.send(data, bcast, discoveryPort);
      } catch (_) {}
    }

    // 3) 手动目标
    for (final target in extraTargets) {
      final idx = target.lastIndexOf(':');
      if (idx <= 0) continue;
      final host = target.substring(0, idx);
      final port = int.tryParse(target.substring(idx + 1)) ?? discoveryPort;
      try {
        socket.send(data, InternetAddress(host), port);
      } catch (_) {}
    }
  }

  /// 子网扫描:按接口【真实子网掩码】计算网段单播探测
  /// (旧版硬编码 /24,/20 等大子网跨段设备互相发现不到,
  /// 组播再被企业 AP 禁掉就彻底失明)。掩码不可得时回退 /24。
  /// 扫描量上限:网段主机数 > 4096 时只扫本地址所在 /22。
  Future<void> _scanSubnet() async {
    final socket = _socket;
    if (socket == null) return;
    final data = _buildPacket();

    final ranges = await _localScanRanges();
    for (final (base, hostBits) in ranges) {
      var count = 1 << hostBits;
      const cap = 1022; // 单网段扫描上限(≈/22)
      final start = count > cap ? (base + ((count - cap) >> 1)) : base + 1;
      final end = count > cap ? start + cap : base + count - 1;
      count = end - start + 1;
      for (var i = 0; i < count; i++) {
        final target = InternetAddress(_intToAddr(start + i));
        try {
          socket.send(data, target, discoveryPort);
        } catch (_) {}
        // 小步快走,避免瞬时突发被交换机丢弃。
        if (i % 32 == 31) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }
    }
  }

  /// 本机各 IPv4 地址所在的 (网络基址, 主机位数的较小值) 列表。
  Future<List<(int base, int hostBits)>> _localScanRanges() async {
    final out = <(int, int)>{};
    if (includeLoopbackScan) {
      out.add((_addrToInt('127.0.0.0'), 8));
    }
    final addrs = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final a in iface.addresses) {
          if (!a.isLoopback) addrs.add(a.address);
        }
      }
    } catch (_) {}
    final masks = await _interfaceMasks();
    for (final a in addrs) {
      final mask = masks[a];
      if (mask != null) {
        final prefix = _maskToPrefix(mask);
        if (prefix >= 8 && prefix <= 32) {
          final ip = _addrToInt(a);
          out.add((
            ip & _maskToInt(mask),
            (32 - prefix).clamp(2, 32)
          ));
          continue;
        }
      }
      // 回退:/24。
      final parts = a.split('.');
      if (parts.length == 4) {
        out.add((_addrToInt('${parts[0]}.${parts[1]}.${parts[2]}.0'), 8));
      }
    }
    return out.toList();
  }

  /// 平台相关的 地址→掩码 表(best effort;失败返回空表走 /24 回退)。
  Future<Map<String, String>> _interfaceMasks() async {
    try {
      if (Platform.isWindows) {
        // ipconfig 输出按语言本地化,但"地址行 + 掩码行"顺序不变:
        // 非 255 开头的点分四段行是地址,其后最近的 255 开头行是掩码。
        final r = await Process.run('ipconfig', []);
        final text = r.stdout as String;
        final lines = text.split('\n');
        final quad = RegExp(r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b');
        String? pendingAddr;
        final out = <String, String>{};
        for (final raw in lines) {
          final m = quad.firstMatch(raw);
          if (m == null) continue;
          final v = m.group(1)!;
          if (v.startsWith('255.')) {
            if (pendingAddr != null) {
              out[pendingAddr] = v;
              pendingAddr = null;
            }
          } else {
            pendingAddr = v;
          }
        }
        return out;
      }
      if (Platform.isLinux) {
        // /proc/net/route:Iface Destination ... Mask(hex LE)。
        final route = await File('/proc/net/route').readAsString();
        final ifaces = <String>{};
        for (final line in route.split('\n').skip(1)) {
          final c = line.trim().split(RegExp(r'\s+'));
          if (c.length >= 8) ifaces.add(c[0]);
        }
        final nameToAddr = <String, String>{};
        for (final iface in await NetworkInterface.list(
            type: InternetAddressType.IPv4, includeLinkLocal: false)) {
          for (final a in iface.addresses) {
            if (!a.isLoopback) nameToAddr[iface.name] = a.address;
          }
        }
        final out = <String, String>{};
        for (final line in route.split('\n').skip(1)) {
          final c = line.trim().split(RegExp(r'\s+'));
          if (c.length < 8) continue;
          final addr = nameToAddr[c[0]];
          if (addr == null) continue;
          final maskHex = c[7];
          if (maskHex.length != 8) continue;
          // 小端十六进制 → 点分掩码。
          final b = [
            int.parse(maskHex.substring(6, 8), radix: 16),
            int.parse(maskHex.substring(4, 6), radix: 16),
            int.parse(maskHex.substring(2, 4), radix: 16),
            int.parse(maskHex.substring(0, 2), radix: 16),
          ];
          if (b.every((x) => x == 0)) continue;
          out[addr] = b.join('.');
        }
        return out;
      }
    } catch (_) {}
    return const {};
  }

  static int _addrToInt(String s) {
    final p = s.split('.');
    if (p.length != 4) return 0;
    return (int.parse(p[0]) << 24) |
        (int.parse(p[1]) << 16) |
        (int.parse(p[2]) << 8) |
        int.parse(p[3]);
  }

  static int _maskToInt(String mask) => _addrToInt(mask);

  static int _maskToPrefix(String mask) {
    var v = _addrToInt(mask);
    var n = 0;
    for (var i = 31; i >= 0; i--) {
      if ((v & (1 << i)) != 0) {
        n++;
      } else if (n > 0) {
        break; // 非连续掩码按前缀长度计
      }
    }
    return n;
  }

  static String _intToAddr(int v) =>
      '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';

  Future<List<InternetAddress>> _broadcastAddresses() async {
    final result = <InternetAddress>[];
    final masks = await _interfaceMasks();
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final mask = masks[addr.address];
          if (mask != null && _maskToPrefix(mask) >= 8) {
            // 按真实掩码计算定向广播地址(旧版 /24 假定)。
            final bcast = _addrToInt(addr.address) |
                (~_maskToInt(mask) & 0xFFFFFFFF);
            result.add(InternetAddress(_intToAddr(bcast)));
            continue;
          }
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          result.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    } catch (_) {}
    if (result.isEmpty) {
      result.add(InternetAddress('255.255.255.255'));
    }
    return result;
  }

  // ------------------------------------------------------------ 接收

  void _onSocketEvent(RawSocketEvent event) {
    final socket = _socket;
    if (socket == null) return;
    if (event == RawSocketEvent.closed) {
      unawaited(_rebindSocket());
      return;
    }
    if (event != RawSocketEvent.read) return;
    try {
      while (true) {
        final dg = socket.receive();
        if (dg == null) break;
        _handleDatagram(dg.data, dg.address.address, dg.port);
      }
    } catch (_) {
      // Windows ICMP 触发的 ConnectionReset 等:吞掉并重建 socket。
      unawaited(_rebindSocket());
    }
  }

  void _handleDatagram(Uint8List data, String host, int srcPort) {
    if (_controller.isClosed) return; // 已销毁
    pb.DiscoveryPacket packet;
    try {
      packet = pb.DiscoveryPacket.fromBuffer(data);
    } catch (_) {
      return; // 无法解析,丢弃
    }
    // 协议指纹校验:magic、版本(v2 起)、非自身、端口合法。
    if (packet.magic != magic) return;
    if (packet.device.protocolVersion != protocolVersion) return;
    if (packet.device.deviceId == identity.deviceId) return;
    if (packet.device.port <= 0 || packet.device.port > 65535) return;

    // 通过基础校验即视为链路活着(接收看门狗依据)。
    _lastRecvAnyMs = DateTime.now().millisecondsSinceEpoch;

    // ---- v2 安全校验 ----
    // 1) 新鲜度:时间戳超出 ±30s 视为重放,直接丢弃
    //    (防止重放旧宣告让已离线设备在别人 UI 里"永远在线")。
    final now = DateTime.now().millisecondsSinceEpoch;
    final ts = packet.timestampMs.toInt();
    if (ts <= 0 || (now - ts).abs() > _freshnessMs) return;
    // 2) 签名:证书 DER + ECDSA 覆盖 timestamp+DeviceInfo,改任何字段即失效。
    //    未携带签名/验签失败一律丢弃(伪造报文无法通过)。
    final certDer = packet.certDer;
    if (certDer.isEmpty || packet.signature.isEmpty) return;
    final msg =
        _announceMessage(ts, packet.device.writeToBuffer());
    if (!Identity.verifyWithCertDer(certDer, msg, packet.signature)) return;
    // 3) 指纹一致:证书 DER 哈希必须等于宣告里声称的指纹
    //    (防"拿别人证书 + 自己的 deviceId"拼凑)。
    final certFpr = sha256.convert(certDer).toString();
    if (packet.device.certFingerprint.isNotEmpty &&
        packet.device.certFingerprint != certFpr) {
      return;
    }

    final id = packet.device.deviceId;
    final existing = _devices[id];
    if (existing != null) {
      existing.lastSeenMs = now;
      _controller.add(existing);
    } else {
      final device = DiscoveredDevice(
        info: packet.device,
        host: host,
        port: packet.device.port,
        lastSeenMs: now,
      );
      _devices[id] = device;
      _controller.add(device);
    }

    // 对陌生来源回执一次,保证扫描方/被扫方互相可见(限频防回环风暴)。
    // v2 回执同样是签名+新鲜度报文,重放无意义。
    final lastReply = _replyCache[host] ?? 0;
    if (now - lastReply > announceInterval.inMilliseconds) {
      _replyCache[host] = now;
      try {
        _socket?.send(_buildPacket(), InternetAddress(host), srcPort);
      } catch (_) {}
    }
  }

  void _expireStale() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ttl = announceInterval.inMilliseconds * 4;
    final expired = <String>[];
    _devices.removeWhere((id, d) {
      final stale = now - d.lastSeenMs > ttl;
      if (stale) expired.add(id);
      return stale;
    });
    for (final id in expired) {
      _expiredController.add(id);
    }
  }

  /// 手动指定地址添加设备(输入 IP,直接发探测)。
  Future<void> probe(String host, {int? port}) async {
    try {
      _socket?.send(_buildPacket(), InternetAddress(host), port ?? discoveryPort);
    } catch (_) {}
  }
}
