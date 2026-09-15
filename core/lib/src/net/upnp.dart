import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UPnP(IGD)端口映射:在家庭路由器上映射本机 gRPC 端口,
/// 获得公网直连端点,绕开 WebRTC 直接建立 gRPC 通道。
///
/// 隐私:默认关闭(设置页开关);映射会消耗一个路由器端口并向
/// 中转服务器公布当前公网 IP:端口(元数据,内容仍全程加密)。
///
/// 安全实现要点:
///  - M-SEARCH 定向 `ST: ...InternetGatewayDevice:1`,校验响应的
///    ST/USN 与 LOCATION 网段——首响应即信会让局域网恶意主机抢先
///    应答,把内网 SOAP 请求(拓扑泄露)发给攻击者,甚至伪造"成功"
///    让本端把攻击者 IP:port 当作自己的公网端点上报给所有同伴;
///  - HTTP 带 connectionTimeout + 总超时,并真正 abort 连接(仅
///    `.timeout()` 弃约不取消,恶意描述服务器可让 socket 永久泄漏);
///  - 映射状态实例化(旧版 static,同进程双实例互删映射);
///  - 有限租期 + 崩溃后自然过期(旧版 LeaseDuration=0 = 永久残留)。
class UpnpMapper {
  UpnpMapper();

  static const _ssdpAddr = '239.255.255.250';
  static const _ssdpPort = 1900;

  /// 最近一次成功映射的控制信息(退出时回收用)。
  ({Uri url, String serviceType, int externalPort})? _lastMapping;

  /// 尝试映射。成功返回公网 (host, port);失败/无 IGD 返回 null。
  /// [timeout] 整体超时(路由器发现+两次 SOAP)。
  Future<({String host, int port})?> mapPort(int internalPort,
      {String description = 'LittleLaw',
      Duration timeout = const Duration(seconds: 5)}) async {
    try {
      return await _mapPort(internalPort, description).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// 回收映射(引擎退出时调用,避免路由器残留端口)。
  /// 幂等:没有映射或已回收时静默返回。
  Future<void> unmapPort() async {
    final m = _lastMapping;
    _lastMapping = null;
    if (m == null) return;
    try {
      await _soapCall(m.url, m.serviceType, 'DeletePortMapping', {
        'NewRemoteHost': '',
        'NewExternalPort': '${m.externalPort}',
        'NewProtocol': 'TCP',
      }).timeout(const Duration(seconds: 3));
    } catch (_) {
      // 路由器不响应/已重启:租期到期自然回收,忽略。
    }
  }

  Future<({String host, int port})?> _mapPort(
      int internalPort, String description) async {
    // 1) SSDP M-SEARCH 发现 IGD。
    final location = await _ssdpDiscover();
    if (location == null) return null;

    // 2) 取设备描述,找 WANIPConnection/WANPPPConnection 控制 URL。
    final controlUrl = await _findControlUrl(location);
    if (controlUrl == null) return null;

    // 3) 本机内网 IP(与路由器同网段)。
    final localIp = await _localIpToward(InternetAddress(location.host));
    if (localIp == null) return null;

    // 4) AddPortMapping:有限租期(崩溃后自动过期,不留永久映射);
    //    外端口冲突时递增重试。
    var mapped = false;
    var externalPort = internalPort;
    for (var i = 0; i < 4 && !mapped; i++) {
      externalPort = internalPort + i;
      final ok = await _soapCall(controlUrl.url, controlUrl.serviceType,
          'AddPortMapping', {
        'NewRemoteHost': '',
        'NewExternalPort': '$externalPort',
        'NewProtocol': 'TCP',
        'NewInternalPort': '$internalPort',
        'NewInternalClient': localIp,
        'NewEnabled': '1',
        'NewPortMappingDescription': description,
        'NewLeaseDuration': '${const Duration(hours: 12).inSeconds}',
      });
      if (ok != null) mapped = true;
    }
    if (!mapped) return null;

    // 记录映射信息,退出时可回收。
    _lastMapping = (
      url: controlUrl.url,
      serviceType: controlUrl.serviceType,
      externalPort: externalPort
    );

    // 5) 公网 IP。
    final externalIp = await _soapCall(controlUrl.url, controlUrl.serviceType,
        'GetExternalIPAddress', {}, returnTag: 'NewExternalIPAddress');
    if (externalIp == null || externalIp.isEmpty) return null;
    return (host: externalIp, port: externalPort);
  }

  Future<Uri?> _ssdpDiscover() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      // 定向搜索网关设备类型(不用 ssdp:all 泛搜)。
      const st = 'urn:schemas-upnp-org:device:InternetGatewayDevice:1';
      final request =
          'M-SEARCH * HTTP/1.1\r\nHOST: $_ssdpAddr:$_ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\nMX: 2\r\nST: $st\r\n\r\n';
      socket.send(utf8.encode(request), InternetAddress(_ssdpAddr), _ssdpPort);

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        final dg = await socket
            .where((e) => e == RawSocketEvent.read)
            .map((_) => socket!.receive())
            .firstWhere((d) => d != null, orElse: () => null)
            .timeout(const Duration(milliseconds: 300),
                onTimeout: () => null);
        if (dg == null) continue;
        final text = utf8.decode(dg.data, allowMalformed: true);
        final locMatch =
            RegExp(r'LOCATION:\s*(\S+)', caseSensitive: false).firstMatch(text);
        if (locMatch == null) continue;
        // 校验 1:响应必须声明所搜的 ST(或其父类型),防伪造应答。
        final stMatch = RegExp(r'(?:ST|USN|NT):\s*urn:schemas-upnp-org:\S*'
                r'(?:InternetGatewayDevice|WANConnection|WANIPConnection)')
            .hasMatch(text);
        if (!stMatch) continue;
        final location = Uri.parse(locMatch.group(1)!);
        // 校验 2:LOCATION 主机须为局域网地址(RFC1918/链路本地),
        // 防止把 SOAP 请求发给公网收集者。
        if (!_isLanHost(location.host)) continue;
        return location;
      }
      return null;
    } finally {
      socket?.close();
    }
  }

  static bool _isLanHost(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false; // 域名形式的 IGD 描述地址:拒绝(从严)
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true;
    if (a == 127) return true;
    return false;
  }

  Future<({Uri url, String serviceType})?> _findControlUrl(
      Uri location) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(location);
      final resp = await req.close()
          .timeout(const Duration(seconds: 4), onTimeout: () {
        req.abort(); // 真正断开,防止恶意描述服务器挂起泄漏 socket
        throw TimeoutException('device description timeout');
      });
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 4));
      // 按服务块配对解析:serviceType 与其后最近的 controlURL 必须在
      // 同一 <service> 块内(旧版全局取"第一个匹配后的第一个 controlURL",
      // 多服务设备可能绑错服务)。
      final blockRe = RegExp(r'<service>(.*?)</service>', dotAll: true);
      final stRe = RegExp(
          r'<serviceType>(urn:schemas-upnp-org:service:(WANIPConnection|WANPPPConnection):1)</serviceType>');
      for (final block in blockRe.allMatches(body)) {
        final m = stRe.firstMatch(block.group(1)!);
        if (m == null) continue;
        final cu = RegExp(r'<controlURL>([^<]+)</controlURL>')
            .firstMatch(block.group(1)!);
        if (cu == null) continue;
        final path = cu.group(1)!;
        final url = path.startsWith('http')
            ? Uri.parse(path)
            : location.replace(path: path);
        if (!_isLanHost(url.host)) continue;
        return (url: url, serviceType: m.group(1)!);
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _localIpToward(InternetAddress routerHost) async {
    try {
      final socket = await Socket.connect(routerHost, 80,
          timeout: const Duration(seconds: 2));
      final ip = socket.address.address;
      socket.destroy();
      return ip;
    } catch (_) {
      // 回退:枚举第一个非回环 IPv4。
      for (final iface
          in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
      return null;
    }
  }

  Future<String?> _soapCall(Uri url, String serviceType, String action,
      Map<String, String> args,
      {String? returnTag}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final argXml = args.entries
          .map((e) => '<${e.key}>${e.value}</${e.key}>')
          .join();
      final envelope = '<?xml version="1.0"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
          '<s:Body><u:$action xmlns:u="$serviceType">$argXml</u:$action></s:Body>'
          '</s:Envelope>';
      final req = await client.postUrl(url);
      req.headers.contentType =
          ContentType('text', 'xml', charset: 'utf-8');
      req.headers.set('SOAPACTION', '"$serviceType#$action"');
      req.write(envelope);
      final resp = await req.close()
          .timeout(const Duration(seconds: 4), onTimeout: () {
        req.abort();
        throw TimeoutException('soap timeout');
      });
      final body = await resp.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return null;
      if (returnTag == null) return '';
      final match = RegExp('<$returnTag>([^<]*)</$returnTag>').firstMatch(body);
      return match?.group(1);
    } finally {
      client.close(force: true);
    }
  }
}
