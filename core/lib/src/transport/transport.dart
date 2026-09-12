import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:grpc/grpc.dart';

import '../identity/identity.dart';

/// 对端连接:TLS + 证书指纹 pinning。
///
/// 两种模式:
///  - pinned: 已知对端指纹(已配对),只接受该指纹,其余一律拒绝。
///  - tofu:   配对前的首次连接,接受任意证书并记录实际指纹,
///            由配对流程用 PIN(SAS)人工绑定真伪。
class PeerChannel {
  PeerChannel._(this.channel);

  final ClientChannel channel;

  String? _observedFingerprint;

  /// 握手时实际观测到的对端证书指纹(pinning 模式下等于 pinned 值)。
  /// TLS 握手发生在首次 RPC 时,此前为 null。
  String? get observedFingerprint => _observedFingerprint;

  /// 建立到对端的通道。
  ///
  /// [pinnedFingerprint] 非空时启用 pinning;为空时 TOFU(仅允许配对服务)。
  static PeerChannel connect({
    required String host,
    required int port,
    String? pinnedFingerprint,
  }) {
    late PeerChannel self;

    bool onBadCertificate(X509Certificate cert, String authority) {
      final fpr = sha256.convert(cert.der).toString();
      self._observedFingerprint = fpr;
      if (pinnedFingerprint == null) return true; // TOFU,配对流程再核验
      return constantTimeHexEquals(fpr, pinnedFingerprint);
    }

    final channel = ClientChannel(
      host,
      port: port,
      options: ChannelOptions(
        credentials: ChannelCredentials.secure(
          // 跳过系统根校验,全部交给指纹判定(自签证书无公共 CA)。
          onBadCertificate: onBadCertificate,
        ),
        connectionTimeout: const Duration(seconds: 10),
        idleTimeout: const Duration(minutes: 5),
      ),
    );
    self = PeerChannel._(channel);
    return self;
  }

  /// 等待底层 TCP+TLS 建立,确保 observedFingerprint 可用。
  Future<void> ensureReady() async {
    await channel.onConnectionStateChanged
        .firstWhere((s) => s == ConnectionState.ready)
        .timeout(const Duration(seconds: 10));
  }

  Future<void> shutdown() => channel.shutdown();
}

bool constantTimeHexEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// 构建并启动本端 gRPC 服务端(TLS,所有服务共用固定端口)。
Future<Server> serveEngine({
  required Identity identity,
  required List<Service> services,
  int port = 0,
  InternetAddress? address,
}) async {
  final server = Server.create(
    services: services,
    // 局域网链路层丢包多,激进一点的心跳保活利于快速发现断线。
    keepAliveOptions: ServerKeepAliveOptions(
      minIntervalBetweenPingsWithoutData: const Duration(seconds: 10),
    ),
  );
  // grpc-dart 服务端在双向流关闭竞态下(对端仍在发送而本地响应流已关)
  // 会向已关闭的 handler 投递数据,抛 "Cannot add event after closing"。
  // 这是 grpc-dart 已知的拆除竞态,无害但有噪音;用受控 Zone 拦截该类错误。
  // 注意:bind 失败(如端口被占)必须经 Completer 传播给调用方,
  // 否则端口退化重试逻辑拿不到异常,启动会卡死。
  final completer = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await server.serve(
          address: address ?? InternetAddress.anyIPv4,
          port: port,
          security: ServerTlsCredentials(
            certificate: Uint8List.fromList(identity.certPem.codeUnits),
            privateKey: Uint8List.fromList(identity.keyPem.codeUnits),
          ),
        );
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    },
    (error, stack) {
      if (error is StateError &&
          error.message.contains('Cannot add event after closing')) {
        return; // 流拆除竞态,忽略
      }
      Zone.current.handleUncaughtError(error, stack);
    },
  );
  await completer.future;
  return server;
}
