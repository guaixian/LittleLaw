/// LittleLaw 核心引擎:局域网 NoServer 端到端加密通讯。
///
/// 架构:
///  - 每个设备 = gRPC Server + Client,固定端口,TLS + 证书指纹 pinning;
///  - 发现:UDP 组播 + 子网扫描;
///  - 配对:TOFU + 6 位 PIN(SAS)人工核对,签发共享会话令牌;
///  - 同步:1:1 会话 ops 日志 + Lamport 时钟,删除双端同步(Telegram 模式);
///  - 文件:元数据走消息通道,数据由接收方拉取,断点续传 + SHA-256 校验。
library littlelaw_core;

import 'dart:async';
import 'dart:io';
import 'package:grpc/grpc.dart';
import 'package:uuid/uuid.dart';

import 'src/discovery/discovery.dart';
import 'src/generated/littlelaw.pb.dart' as pb;
import 'src/crypto/file_vault.dart';
import 'src/identity/identity.dart';
import 'src/net/upnp.dart';
import 'src/oob/blob.dart';
import 'src/oob/lan_oob.dart';
import 'src/pairing/pairing.dart';
import 'src/rendezvous/rendezvous.dart';
import 'src/store/store.dart';
import 'src/sync/sync_engine.dart';
import 'src/transfer/transfer.dart';
import 'src/transport/transport.dart';

export 'src/discovery/discovery.dart' show DiscoveredDevice;
export 'src/identity/identity.dart' show Identity;
export 'src/oob/blob.dart' show OobBlob;
export 'src/oob/base45.dart' show Base45;
export 'src/oob/lan_oob.dart' show LanOobPayload;
export 'src/oob/qr_chunker.dart' show QrChunker, QrReassembler;
export 'src/rendezvous/rendezvous.dart'
    show RendezvousClient, RendezvousSignal, RendezvousMail, RendezvousPeerOnline;
export 'src/net/upnp.dart' show UpnpMapper;
export 'src/pairing/pairing.dart' show PairRequestEvent, PairResult;
export 'src/store/store.dart'
    show Message, Peer, Store, Group, ConvSummary;
export 'src/crypto/backup_codec.dart' show BackupCodec;
export 'src/crypto/file_vault.dart' show FileVault;
export 'src/sync/sync_engine.dart'
    show
        EngineEvent,
        MessageAdded,
        MessagesDeleted,
        ClipboardReceived,
        PeerStatusChanged,
        FileMessageArrived,
        FileCancelled,
        FileFetchRequested,
        FileDataReceived,
        FileDataAcked,
        CallOfferReceived,
        CallAnswerReceived,
        CallCandidateReceived,
        CallEndReceived,
        GroupSynced,
        ReceiptsUpdated,
        ReactionsChanged,
        ProfileUpdated,
        MessageStateChanged;
export 'src/generated/littlelaw.pb.dart'
    show
        Envelope,
        LinkAuth,
        CallOffer,
        CallAnswer,
        CallCandidate,
        CallEnd,
        GroupSync,
        ReadReceipt,
        ReactionUpdate;
export 'src/transport/auth.dart' show Auth;
export 'src/transfer/transfer.dart' show TransferProgress;

/// 引擎门面:Flutter UI 只与这个类交互。
class LittleLawEngine {
  LittleLawEngine._({
    required this.identity,
    required this.store,
    required this.discovery,
    required this.pairing,
    required this.sync,
    required this.transfer,
    required this.grpcPort,
    required Server server,
    required this.dataDir,
  }) : _server = server;

  /// 固定协议端口(正式部署时全端一致)。
  static const defaultGrpcPort = 47520;

  final Identity identity;
  final Store store;
  final DiscoveryService discovery;
  final PairingManager pairing;
  final SyncEngine sync;
  final TransferManager transfer;
  final int grpcPort;
  final String dataDir;
  final Server _server;

  /// 可选的中转服务器客户端(配置了 rendezvousUrl 才存在)。
  RendezvousClient? rendezvous;

  StreamSubscription<DiscoveredDevice>? _discoverySub;
  StreamSubscription<String>? _discoveryExpiredSub;

  // ------------------------------------------------------------ 生命周期

  /// 启动引擎:加载身份 → 开库 → 起服务 → 开发现 → 恢复会话。
  ///
  /// [grpcPort] 传 0 时由系统分配(同机多实例测试用),正式部署用固定端口。
  static Future<LittleLawEngine> start({
    required String dataDir,
    int grpcPort = defaultGrpcPort,
    int discoveryPort = DiscoveryService.defaultDiscoveryPort,
    String? deviceName,
    String? deviceModel,
    List<String> discoveryTargets = const [],
    bool includeLoopbackScan = false,
    bool autoAcceptFiles = true,
    String? rendezvousUrl,
    bool upnpEnabled = false,
    bool encryptFilesAtRest = false,
  }) async {
    final identity = await Identity.loadOrCreate(dataDir,
        deviceName: deviceName, deviceModel: deviceModel);

    final store = Store()..open('$dataDir/littlelaw.db');

      // 引擎注入本机 ID(群收件人过滤)。
      store.selfDeviceId = identity.deviceId;
      final sync = SyncEngine(identity: identity, store: store);
    final pairing = PairingManager(
      identity: identity,
      store: store,
      grpcPort: grpcPort,
    );
    // 落盘加密(可选):收到的文件以密文按设备/类型分目录存放。
    final vault =
        encryptFilesAtRest ? await FileVault.open(dataDir) : null;
    final transfer = TransferManager(
      identity: identity,
      store: store,
      sync: sync,
      inboxDir: '$dataDir/inbox',
      autoAcceptFiles: autoAcceptFiles,
      vault: vault,
    );

    Server server;
    try {
      server = await serveEngine(
        identity: identity,
        services: [pairing, sync, transfer],
        port: grpcPort,
      );
    } on SocketException {
      // 固定端口被占用(如同机第二个实例):退化为系统分配端口。
      // 发现报文携带实际端口,不影响互通。
      server = await serveEngine(
        identity: identity,
        services: [pairing, sync, transfer],
        port: 0,
      );
    }
    final boundPort = server.port ?? grpcPort;

    final discovery = DiscoveryService(
      identity: identity,
      grpcPort: boundPort,
      discoveryPort: discoveryPort,
      extraTargets: discoveryTargets,
      includeLoopbackScan: includeLoopbackScan,
    );

    final engine = LittleLawEngine._(
      identity: identity,
      store: store,
      discovery: discovery,
      pairing: pairing,
      sync: sync,
      transfer: transfer,
      grpcPort: boundPort,
      server: server,
      dataDir: dataDir,
    );

    transfer.start();

    // 资料/头像同步接线:会话建立互推 + 变更广播;收到即落盘并通知 UI。
    sync.profileProvider = () {
      try {
        final f = File('${engine.avatarDir}/me.png');
        if (f.existsSync() && f.lengthSync() <= 96 * 1024) {
          return pb.ProfileUpdate(
              deviceName: identity.deviceName,
              avatarPng: f.readAsBytesSync());
        }
      } catch (_) {}
      return pb.ProfileUpdate(deviceName: identity.deviceName);
    };
    sync.onProfileUpdate = (peerId, profile) {
      if (profile.deviceName.isNotEmpty) {
        store.updatePeerName(peerId, profile.deviceName);
      }
      if (profile.avatarPng.isNotEmpty) {
        try {
          final f = File(engine.peerAvatarPath(peerId));
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(profile.avatarPng);
        } catch (_) {}
      }
      sync.emitLocal(ProfileUpdated(peerId));
    };
    sync.onGroupAvatar = (groupId, png) {
      try {
        final f = File(engine.groupAvatarPath(groupId));
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(png);
      } catch (_) {}
    };

    // 可选:挂接中转服务器(离线邮箱兜底 + presence + 信令)。
    if (rendezvousUrl != null && rendezvousUrl.isNotEmpty) {
      // UPnP 端口映射(可选):获得公网直连端点,注册时上报。
      String? endpoint;
      if (upnpEnabled) {
        final mapped = await UpnpMapper.mapPort(boundPort,
            timeout: const Duration(seconds: 4));
        if (mapped != null) {
          endpoint = '${mapped.host}:${mapped.port}';
        }
      }
      final rc = RendezvousClient(
          identity: identity,
          store: store,
          url: rendezvousUrl,
          endpoint: endpoint);
      sync.attachRendezvous(rc);
      pairing.onPeersChanged = rc.subscribePeers;
      // 受邀方应答经服务器推回:回退用邀请令牌解密,统一走 WebRTC 应用路径。
      rc.fallbackTokenProvider = () => pairing.pendingRemoteOfferToken;
      rc.pairAnswers.listen(pairing.noteRemoteAnswer);
      rc.start();
      engine.rendezvous = rc;
    }

    // 发现到可信设备 → 刷新地址并确保会话在线。
    engine._discoverySub = discovery.devices.listen((d) {
      final peer = store.getPeer(d.deviceId);
      if (peer != null) {
        sync.notePeerAddress(peer, d.host, d.port);
      }
    });

    // 设备从局域网消失(报文超时)→ 标记离线。但若 TCP/WebRTC 会话仍活着
    // (组播被路由器/系统限流很常见),不拆会话——避免在线状态反复横跳。
    engine._discoveryExpiredSub = discovery.expiredDevices.listen((deviceId) {
      if (store.getPeer(deviceId) != null && !sync.isOnline(deviceId)) {
        sync.forceDisconnect(deviceId);
      }
    });

    await discovery.start();
    sync.bootstrapSessions();
    return engine;
  }

  Future<void> dispose() async {
    await _discoverySub?.cancel();
    await _discoveryExpiredSub?.cancel();
    await rendezvous?.dispose();
    await discovery.dispose();
    // 回收 UPnP 端口映射(避免路由器残留)。
    await UpnpMapper.unmapPort();
    // 先关闭全部通道(客户端 + 服务端流),再关停 server,避免挂起。
    await sync.dispose();
    await transfer.dispose();
    // 清理文件解密缓存。
    await vault?.clearCache();
    await pairing.dispose();
    await _server.shutdown().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    store.dispose();
  }

  // ------------------------------------------------------------ 事件流

  /// 发现层设备出现/刷新。
  Stream<DiscoveredDevice> get discoveredDevices => discovery.devices;

  /// 待批准的配对请求(弹 PIN 核对框)。
  Stream<PairRequestEvent> get pairRequests => pairing.requests;

  /// 聊天/删除/剪贴板/在线状态事件。
  Stream<EngineEvent> get events => sync.events;

  /// 文件传输进度。
  Stream<TransferProgress> get transferProgress => transfer.progress;

  // ------------------------------------------------------------ 配对

  /// 向发现的设备发起配对。返回结果含 PIN,需与对端弹窗核对。
  Future<PairResult> requestPair(DiscoveredDevice device) =>
      pairing.requestPairWith(device.host, device.port);

  /// 响应配对请求(UI 用户点击)。
  void respondPair(String requestId, bool accept) =>
      pairing.respond(requestId, accept);

  /// 主动方展示的 PIN(与对端弹窗同源算法)。
  String pinFor(String peerFingerprint) => pairing.pinFor(peerFingerprint);

  /// 解除配对(双端数据同步清除)。
  Future<void> unpair(String deviceId) async {
    final peer = store.getPeer(deviceId);
    if (peer == null) return;
    await pairing.unpairWith(peer);
  }

  // ------------------------------------------------------------ OOB 远程配对

  /// (邀请方)开始远程邀请,返回共享令牌(由 app 层组装 offer 引导包)。
  String beginRemoteOffer() => pairing.beginRemoteOffer();

  /// (受邀方)应用 offer 引导包,完成配对入账。
  Peer acceptRemoteOffer(OobBlob blob) => pairing.acceptRemoteOffer(blob);

  /// (邀请方)应用 answer 引导包(校验令牌回显),完成配对入账。
  Peer acceptRemoteAnswer(OobBlob blob) => pairing.acceptRemoteAnswer(blob);

  /// 放弃进行中的邀请。
  void cancelRemoteOffer() => pairing.cancelRemoteOffer();

  /// 本机全部局域网 gRPC 地址候选(host:port)。
  Future<List<String>> localGrpcAddresses() async {
    final addresses = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          addresses.add('${addr.address}:$grpcPort');
        }
      }
    } catch (_) {}
    return addresses;
  }

  /// 收到的远程应答(app 层应用到 WebRTC 完成链路)。
  Stream<String> get answerDeliveries => pairing.answerDeliveries;

  /// (受邀方)把 answer 引导包自动回传给邀请方(地址可达时免手动粘贴)。
  Future<void> deliverAnswerTo(String host, int port, String answerBlob) =>
      pairing.deliverAnswerTo(host, port, answerBlob);

  /// (受邀方)经指定中转服务器一次性回传配对应答(本机未配置服务器时用)。
  Future<void> deliverPairAnswerOnce(
          String rendezvousUrl, String toPeerId, String answerBlob) =>
      RendezvousClient.deliverPairAnswerOnce(
        identity: identity,
        store: store,
        rendezvousUrl: rendezvousUrl,
        toPeerId: toPeerId,
        answerBlob: answerBlob,
      );

  /// 开启免 PIN 配对窗口,返回二维码/NFC 用的局域网载荷字符串(2 分钟有效)。
  /// 载荷内含本机全部局域网地址候选与一次性 tap 令牌。
  Future<String> enableTapPairing() async {
    final tapToken = pairing.generateTapToken();
    final addresses = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          addresses.add('${addr.address}:$grpcPort');
        }
      }
    } catch (_) {}
    return LanOobPayload(
      tapToken: tapToken,
      addresses: addresses,
      deviceId: identity.deviceId,
      deviceName: identity.deviceName,
      fingerprint: identity.fingerprint,
    ).encode();
  }

  /// (读取方)凭二维码/NFC 载荷完成免 PIN 配对。
  Future<PairResult> pairViaLanOob(String encoded) async {
    final payload = LanOobPayload.decode(encoded);
    Object? lastError;
    for (final addr in payload.addresses) {
      final idx = addr.lastIndexOf(':');
      if (idx <= 0) continue;
      final host = addr.substring(0, idx);
      final port = int.tryParse(addr.substring(idx + 1));
      if (port == null) continue;
      try {
        return await pairing.pairViaTap(host, port, payload.tapToken);
      } catch (e) {
        lastError = e; // 尝试下一个地址候选
      }
    }
    throw StateError('所有地址候选均不可达: $lastError');
  }

  /// 注册外部传输链路(WebRTC DataChannel 等,由 app 层建立并鉴权后挂载)。
  /// 返回的 sink 用于向对端发送信封。
  StreamController<pb.Envelope> attachExternalTransport(
          String peerId, Stream<pb.Envelope> incoming) =>
      sync.attachExternalTransport(peerId, incoming);

  /// 断开外部传输链路。
  void detachExternalTransport(
          String peerId, StreamController<pb.Envelope> sink) =>
      sync.detachExternalTransport(peerId, sink);

  // ------------------------------------------------------------ 聊天

  Future<Message> sendText(String peerId, String text) =>
      sync.sendText(peerId, text);

  Future<Message> sendFile(String peerId, String filePath, {int? kind}) =>
      transfer.sendFileTo(peerId, filePath, kind: kind);

  Future<void> deleteMessages(String peerId, List<String> msgIds,
          {bool clearAll = false}) =>
      sync.deleteMessages(peerId, msgIds, clearAll: clearAll);

  void sendClipboard(String peerId, String text) =>
      sync.sendClipboard(peerId, text);

  /// 拉取/续传文件(autoAcceptFiles 关闭时由 UI 触发)。
  Future<void> receiveFile(String peerId, Message msg) =>
      transfer.receiveFile(peerId, msg);

  void cancelReceive(String fileId) => transfer.cancelReceive(fileId);

  // ------------------------------------------------------------ 查询

  List<Peer> get peers => store.allPeers();

  Peer? peerById(String deviceId) => store.getPeer(deviceId);

  bool isOnline(String peerId) => sync.isOnline(peerId);

  String convIdOf(String peerId) =>
      Store.convIdFor(identity.deviceId, peerId);

  List<Message> loadMessages(String peerId,
      {int limit = 200, int? beforeLamport}) {
    return store.listMessages(convIdOf(peerId),
        limit: limit, beforeLamport: beforeLamport);
  }

  /// 手动添加设备(输入 IP 直接探测)。
  Future<void> probeDevice(String host) => discovery.probe(host);

  /// 设备改名(同步到发现层后续 announce)。
  Future<void> renameDevice(String newName) =>
      identity.rename(dataDir, newName);

  /// 标记/取消"我的设备"(多设备镜像)。
  void setSelfDevice(String deviceId, bool isSelf) =>
      store.setSelfDevice(deviceId, isSelf);

  bool isSelfDevice(String deviceId) => store.isSelfDevice(deviceId);

  /// 判定消息气泡归属:"我"= 本机或我的设备发出。
  bool isFromMe(String senderId) =>
      senderId == identity.deviceId || isSelfDevice(senderId);

  /// 本机收件箱目录。
  String get inboxDir => '$dataDir/inbox';

  /// SQLite WAL 落盘(备份前调用)。
  void checkpointDb() => store.checkpoint();

  // ------------------------------------------------------------ 头像 / 资料

  /// 头像目录:<dataDir>/avatars/{me,peer_<id>,group_<id>}.png
  String get avatarDir => '$dataDir/avatars';

  String myAvatarPath() => '$avatarDir/me.png';
  String peerAvatarPath(String deviceId) => '$avatarDir/peer_$deviceId.png';
  String groupAvatarPath(String groupId) => '$avatarDir/group_$groupId.png';

  /// 设置我的头像(PNG ≤96KB)并广播。
  Future<void> setMyAvatar(List<int> pngBytes) async {
    final f = File(myAvatarPath());
    await f.parent.create(recursive: true);
    await f.writeAsBytes(pngBytes);
    sync.broadcastProfile();
  }

  /// 设置群头像并扇出群定义。
  Future<void> setGroupAvatar(String groupId, List<int> pngBytes) async {
    final g = store.getGroup(groupId);
    if (g == null) return;
    final f = File(groupAvatarPath(groupId));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(pngBytes);
    sync.broadcastGroupSync(g, avatarPng: pngBytes);
  }

  /// 当前群头像字节(扇出用),无则 null。
  List<int>? _groupAvatarBytes(String groupId) {
    try {
      final f = File(groupAvatarPath(groupId));
      if (f.existsSync() && f.lengthSync() <= 96 * 1024) {
        return f.readAsBytesSync();
      }
    } catch (_) {}
    return null;
  }

  /// 文件落盘加密(encryptFilesAtRest 开启时非空)。
  FileVault? get vault => transfer.vault;

  /// 解密消息附件到缓存并返回明文路径(查看/打开/分享用)。
  /// 未启用加密时直接返回原路径。
  Future<String> plaintextPathFor(Message msg) async {
    final p = msg.filePath;
    final v = vault;
    if (p == null) throw StateError('file not downloaded');
    if (v == null || !p.endsWith(FileVault.encExt)) return p;
    return v.decryptToCache(p, 'msg-${msg.msgId}-'
        '${p.split(Platform.pathSeparator).last}');
  }

  /// 解锁回执计数入口(UI 刷新会话未读徽标用)。
  List<ConvSummary> conversationSummaries() =>
      store.conversationSummaries(identity.deviceId);

  // ------------------------------------------------------------ 群聊

  /// 创建群(成员含本机自动加入)并扇出群定义给全体成员。
  Group createGroup(String name, List<String> memberDeviceIds) {
    final id = const Uuid().v4();
    final group = Group(
      id: id,
      name: name,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      memberIds: [identity.deviceId, ...memberDeviceIds],
    );
    store.insertGroup(group);
    sync.broadcastGroupSync(group);
    return group;
  }

  /// 改群名并扇出。
  void renameGroup(String groupId, String newName) {
    final g = store.getGroup(groupId);
    if (g == null) return;
    final updated = Group(
      id: groupId,
      name: newName,
      createdAtMs: g.createdAtMs,
      memberIds: g.memberIds,
    );
    store.insertGroup(updated);
    sync.broadcastGroupSync(updated,
        avatarPng: _groupAvatarBytes(groupId));
  }

  /// 拉人入群:更新定义并扇出(新成员额外直推)。
  void addGroupMembers(String groupId, List<String> ids) {
    final g = store.getGroup(groupId);
    if (g == null) return;
    final next = <String>{...g.memberIds, ...ids}.toList();
    final updated = Group(
      id: groupId,
      name: g.name,
      createdAtMs: g.createdAtMs,
      memberIds: next,
    );
    store.insertGroup(updated);
    sync.broadcastGroupSync(updated,
        extraTargets: ids.toSet(), avatarPng: _groupAvatarBytes(groupId));
  }

  /// 踢人:被移出者收到"不含自己"的定义后删除本地群与消息。
  void removeGroupMembers(String groupId, List<String> ids) {
    final g = store.getGroup(groupId);
    if (g == null) return;
    final removed = ids.where((id) => id != identity.deviceId).toSet();
    if (removed.isEmpty) return;
    final next =
        g.memberIds.where((id) => !removed.contains(id)).toList();
    final updated = Group(
      id: groupId,
      name: g.name,
      createdAtMs: g.createdAtMs,
      memberIds: next,
    );
    store.insertGroup(updated);
    sync.broadcastGroupSync(updated,
        extraTargets: removed, avatarPng: _groupAvatarBytes(groupId));
  }

  /// 退群:本地删定义保留历史,其余成员收到更新。
  void leaveGroup(String groupId) {
    final g = store.getGroup(groupId);
    if (g == null) return;
    final next =
        g.memberIds.where((id) => id != identity.deviceId).toList();
    if (next.isEmpty) {
      dissolveGroup(groupId); // 只剩自己:直接解散
      return;
    }
    final updated = Group(
      id: groupId,
      name: g.name,
      createdAtMs: g.createdAtMs,
      memberIds: next,
    );
    store.deleteGroup(groupId, keepMessages: true);
    sync.broadcastGroupSync(updated);
    sync.emitLocal(GroupSynced(groupId));
  }

  /// 解散群:通知全体成员 + 我的设备,各端删除群与消息。
  void dissolveGroup(String groupId) {
    final g = store.getGroup(groupId);
    if (g == null) return;
    sync.broadcastGroupSync(g, dissolve: true);
    store.deleteGroup(groupId);
    sync.emitLocal(GroupSynced(groupId));
  }

  // ------------------------------------------------ 已读回执 / 表情回应

  /// 标记会话已读(convKey:群 ID 或对方设备 ID)。
  void markRead(String convKey) => sync.markRead(convKey);

  /// 设置/取消表情回应(emoji 空串=取消)。
  void setReaction(String convKey, String msgId, String emoji) =>
      sync.setReaction(convKey, msgId, emoji);
  /// 重发消息:文本/自己发的文件重推元数据;收到的文件消息触发重新拉取。
  Future<void> resendMessage(String msgId) async {
    final m = store.getMessage(msgId);
    if (m == null) return;
    final mine = m.senderId == identity.deviceId || isSelfDevice(m.senderId);
    if (!mine) {
      if (Message.hasFilePayload(m.kind) && m.fileId != null) {
        final convKey = m.convId.startsWith('g:')
            ? m.convId.substring(2)
            : m.convId
                .split(':')
                .firstWhere((p) => p != identity.deviceId,
                    orElse: () => m.convId.split(':').first);
        await transfer.receiveFile(convKey, m);
      }
      return;
    }
    sync.repushMessage(m);
  }

  /// 全库消息搜索(文本 + 文件名)。
  List<Message> searchMessages(String query, {int limit = 200}) =>
      store.searchMessages(query, limit: limit);

  /// 发送语音消息(1:1)。
  Future<Message> sendVoice(String peerId, String filePath, int durationMs) =>
      transfer.sendFileTo(peerId, filePath,
          kind: Message.kindVoice, durationMs: durationMs);

  /// 发送语音消息(群)。
  Future<Message> sendGroupVoice(String groupId, String filePath, int durationMs) =>
      transfer.sendGroupFileTo(groupId, filePath,
          kind: Message.kindVoice, durationMs: durationMs);

  /// 群剪贴板同步(扇出)。
  void sendGroupClipboard(String groupId, String text) =>
      sync.sendGroupClipboard(groupId, text);

  List<Group> get groups => store.allGroups();

  Group? groupById(String groupId) => store.getGroup(groupId);

  Future<Message> sendGroupText(String groupId, String text) =>
      sync.sendGroupText(groupId, text);

  Future<Message> sendGroupFile(String groupId, String filePath) =>
      transfer.sendGroupFileTo(groupId, filePath);

  Future<Message> sendGroupFileAs(String groupId, String filePath,
          {required int kind, int durationMs = 0}) =>
      transfer.sendGroupFileTo(groupId, filePath,
          kind: kind, durationMs: durationMs);

  Future<void> deleteGroupMessages(String groupId, List<String> msgIds,
          {bool clearAll = false}) =>
      sync.deleteGroupMessages(groupId, msgIds, clearAll: clearAll);

  List<Message> loadGroupMessages(String groupId,
          {int limit = 200, int? beforeLamport}) =>
      store.listMessages(Group.convIdOf(groupId),
          limit: limit, beforeLamport: beforeLamport);

  String groupConvId(String groupId) => Group.convIdOf(groupId);
}
