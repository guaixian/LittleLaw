import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UPnP(IGD)端口映射:在家庭路由器上映射本机 gRPC 端口,
/// 获得公网直连端点,绕开 WebRTC 直接建立 gRPC 通道。
///
/// 隐私:默认关闭(设置页开关);映射会消耗一个路由器端口并向
/// 中转服务器公布当前公网 IP:端口(元数据,内容仍全程加密)。
class UpnpMapper {
  UpnpMapper._();

  static const _ssdpAddr = '239.255.255.250';
  static const _ssdpPort = 1900;

  /// 最近一次成功映射的控制信息(退出时回收用)。
  static ({Uri url, String serviceType, int externalPort})? _lastMapping;

  /// 尝试映射。成功返回公网 (host, port);失败/无 IGD 返回 null。
  /// [timeout] 整体超时(路由器发现+两次 SOAP)。
  static Future<({String host, int port})?> mapPort(int internalPort,
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
  static Future<void> unmapPort() async {
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
      // 路由器不响应/已重启:映射自然过期,忽略。
    }
  }

  static Future<({String host, int port})?> _mapPort(
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

    // 4) AddPortMapping(内外同端口)。
    final ok = await _soapCall(controlUrl.url, controlUrl.serviceType,
        'AddPortMapping', {
      'NewRemoteHost': '',
      'NewExternalPort': '$internalPort',
      'NewProtocol': 'TCP',
      'NewInternalPort': '$internalPort',
      'NewInternalClient': localIp,
      'NewEnabled': '1',
      'NewPortMappingDescription': description,
      'NewLeaseDuration': '0',
    });
    if (ok == null) return null;

    // 记录映射信息,退出时可回收。
    _lastMapping = (
      url: controlUrl.url,
      serviceType: controlUrl.serviceType,
      externalPort: internalPort
    );

    // 5) 公网 IP。
    final externalIp = await _soapCall(controlUrl.url, controlUrl.serviceType,
        'GetExternalIPAddress', {}, returnTag: 'NewExternalIPAddress');
    if (externalIp == null || externalIp.isEmpty) return null;
    return (host: externalIp, port: internalPort);
  }

  static Future<Uri?> _ssdpDiscover() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final request =
          'M-SEARCH * HTTP/1.1\r\nHOST: $_ssdpAddr:$_ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n';
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
        final match = RegExp(r'LOCATION:\s*(\S+)', caseSensitive: false)
            .firstMatch(text);
        if (match != null) {
          return Uri.parse(match.group(1)!);
        }
      }
      return null;
    } finally {
      socket?.close();
    }
  }

  static Future<({Uri url, String serviceType})?> _findControlUrl(
      Uri location) async {
    final client = HttpClient();
    try {
      final resp = await (await client.getUrl(location)).close();
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      // WANIPConnection:1 或 WANPPPConnection:1
      final stMatch = RegExp(
              r'<serviceType>(urn:schemas-upnp-org:service:(WANIPConnection|WANPPPConnection):1)</serviceType>')
          .firstMatch(body);
      if (stMatch == null) return null;
      final serviceType = stMatch.group(1)!;
      // 该服务对应的 controlURL(取 serviceType 之后最近的 controlURL)。
      final after = body.substring(stMatch.end);
      final cuMatch =
          RegExp(r'<controlURL>([^<]+)</controlURL>').firstMatch(after);
      if (cuMatch == null) return null;
      final path = cuMatch.group(1)!;
      final url = path.startsWith('http')
          ? Uri.parse(path)
          : location.replace(path: path);
      return (url: url, serviceType: serviceType);
    } finally {
      client.close();
    }
  }

  static Future<String?> _localIpToward(InternetAddress routerHost) async {
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

  static Future<String?> _soapCall(Uri url, String serviceType, String action,
      Map<String, String> args,
      {String? returnTag}) async {
    final client = HttpClient();
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
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return null;
      if (returnTag == null) return '';
      final match = RegExp('<$returnTag>([^<]*)</$returnTag>').firstMatch(body);
      return match?.group(1);
    } finally {
      client.close();
    }
  }
}
