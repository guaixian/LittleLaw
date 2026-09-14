import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  static const protocolVersion = '1';

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

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    socket.broadcastEnabled = true;
    try {
      socket.joinMulticast(InternetAddress(multicastGroup));
    } catch (_) {
      // 某些平台/网卡不支持组播,降级为广播+扫描,不致命。
    }
    _socketSub = socket.listen(_onSocketEvent);

    _announceTimer = Timer.periodic(announceInterval, (_) => unawaited(_announce()));
    _scanTimer = Timer.periodic(scanInterval, (_) => unawaited(_scanSubnet()));
    // 过期检测频率 = 宣告间隔,保证离线判定延迟稳定在 TTL±interval。
    _expiryTimer = Timer.periodic(announceInterval, (_) => _expireStale());

    await _announce();
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
    // 先停订阅再关 socket,防止在途报文写入已关闭的流。
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    _replyCache.clear();
    // 控制器保留,stop 后可重新 start。
  }

  /// 彻底销毁(不可再 start)。引擎退出时调用。
  Future<void> dispose() async {
    await stop();
    if (!_expiredController.isClosed) await _expiredController.close();
    if (!_controller.isClosed) await _controller.close();
  }

  // ------------------------------------------------------------ 发送

  Uint8List _buildPacket() {
    final packet = pb.DiscoveryPacket(
      magic: magic,
      timestampMs: Int64(DateTime.now().millisecondsSinceEpoch),
      device: pb.DeviceInfo(
        deviceId: identity.deviceId,
        deviceName: identity.deviceName,
        platform: Identity.platformName(),
        certFingerprint: identity.fingerprint,
        port: grpcPort,
        protocolVersion: protocolVersion,
        deviceModel: identity.deviceModel,
      ),
    );
    return packet.writeToBuffer();
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

  /// 子网扫描:对本机每个 IPv4 /24 段单播探测。量小(254 包/段/15s),
  /// 在组播与广播都被禁的网络里保证可达。
  Future<void> _scanSubnet() async {
    final socket = _socket;
    if (socket == null) return;
    final data = _buildPacket();

    final prefixes = <String>{};
    if (includeLoopbackScan) prefixes.add('127.0.0');
    for (final iface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    )) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        final parts = addr.address.split('.');
        if (parts.length != 4) continue;
        prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }

    for (final prefix in prefixes) {
      for (var i = 1; i < 255; i++) {
        final target = InternetAddress('$prefix.$i');
        try {
          socket.send(data, target, discoveryPort);
        } catch (_) {}
        // 小步快走,避免瞬时突发被交换机丢弃。
        if (i % 32 == 0) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }
    }
  }

  Future<List<InternetAddress>> _broadcastAddresses() async {
    final result = <InternetAddress>[];
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          // /24 假定:家用/办公局域网最常见形态。
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
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    while (true) {
      final dg = socket.receive();
      if (dg == null) break;
      _handleDatagram(dg.data, dg.address.address, dg.port);
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
    // 协议指纹三重校验:magic、版本、非自身。
    if (packet.magic != magic) return;
    if (packet.device.protocolVersion != protocolVersion) return;
    if (packet.device.deviceId == identity.deviceId) return;
    if (packet.device.port <= 0 || packet.device.port > 65535) return;

    final now = DateTime.now().millisecondsSinceEpoch;
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
