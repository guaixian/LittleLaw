import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:uuid/uuid.dart';

import '../generated/littlelaw.pb.dart' as pb;
import '../generated/littlelaw.pbgrpc.dart' as pbg;
import '../identity/identity.dart';
import '../rendezvous/rendezvous.dart';
import '../store/store.dart';
import '../transport/auth.dart';
import '../transport/transport.dart';
import '../util.dart';

// ---------------------------------------------------------------------------
// 引擎事件(UI 与传输层共用)
// ---------------------------------------------------------------------------

sealed class EngineEvent {}

class MessageAdded extends EngineEvent {
  MessageAdded(this.peerId, this.message);
  final String peerId;
  final Message message;
}

class MessagesDeleted extends EngineEvent {
  MessagesDeleted(this.peerId, this.msgIds, this.clearAll);
  final String peerId;
  final List<String> msgIds;
  final bool clearAll;
}

class ClipboardReceived extends EngineEvent {
  ClipboardReceived(this.peerId, this.text);
  final String peerId;
  final String text;
}

class PeerStatusChanged extends EngineEvent {
  PeerStatusChanged(this.peerId, this.online);
  final String peerId;
  final bool online;
}

/// 文件消息到达(供传输层决定是否自动拉取)。
class FileMessageArrived extends EngineEvent {
  FileMessageArrived(this.peerId, this.message);
  final String peerId;
  final Message message;
}

class FileCancelled extends EngineEvent {
  FileCancelled(this.peerId, this.fileId);
  final String peerId;
  final String fileId;
}

/// 对端请求拉取文件(信封式,传输层无关,WebRTC 链路等场景使用)。
class FileFetchRequested extends EngineEvent {
  FileFetchRequested(this.peerId, this.fileId, this.offset);
  final String peerId;
  final String fileId;
  final int offset;
}

/// 收到信封式文件数据帧。
class FileDataReceived extends EngineEvent {
  FileDataReceived(this.peerId, this.data);
  final String peerId;
  final pb.FileData data;
}

/// 收到信封式文件数据回执(窗口背压)。
class FileDataAcked extends EngineEvent {
  FileDataAcked(this.peerId, this.fileId, this.ackedOffset);
  final String peerId;
  final String fileId;
  final int ackedOffset;
}

/// 收到通话发起。
class CallOfferReceived extends EngineEvent {
  CallOfferReceived(this.peerId, this.offer);
  final String peerId;
  final pb.CallOffer offer;
}

/// 收到通话应答。
class CallAnswerReceived extends EngineEvent {
  CallAnswerReceived(this.peerId, this.answer);
  final String peerId;
  final pb.CallAnswer answer;
}

/// 收到通话 ICE 候选。
class CallCandidateReceived extends EngineEvent {
  CallCandidateReceived(this.peerId, this.candidate);
  final String peerId;
  final pb.CallCandidate candidate;
}

/// 收到通话结束(挂断/拒绝/失败)。
class CallEndReceived extends EngineEvent {
  CallEndReceived(this.peerId, this.end);
  final String peerId;
  final pb.CallEnd end;
}

/// 收到群定义(建群/改群/解散)。
class GroupSynced extends EngineEvent {
  GroupSynced(this.groupId);
  final String groupId;
}

/// 已读回执到达(自己发出的消息被对方读了)。
class ReceiptsUpdated extends EngineEvent {
  ReceiptsUpdated(this.convKey, this.msgIds);
  final String convKey; // 群 ID 或对方设备 ID
  final List<String> msgIds;
}

/// 表情回应更新(单条消息)。
class ReactionsChanged extends EngineEvent {
  ReactionsChanged(this.convKey, this.msgId);
  final String convKey; // 群 ID 或对方设备 ID
  final String msgId;
}

/// 对端资料(名称/头像)到达。
class ProfileUpdated extends EngineEvent {
  ProfileUpdated(this.peerId);
  final String peerId;
}

/// 本端消息发送状态变化(发送中/成功/失败)。
class MessageStateChanged extends EngineEvent {
  MessageStateChanged(this.msgId);
  final String msgId;
}

// ---------------------------------------------------------------------------
// 同步引擎:1:1 会话的端到端一致同步。
//
// 一致性模型:
//  - 本端变更(发消息/删消息)先落库 + 追加 ops,再尝试在线推送;
//  - 对端不在线时 ops 留表,重连后按对方 Hello 携带的游标补发;
//  - 所有 op 幂等(msg_id 主键 / 删除可重入),双通道重复投递无害;
//  - 删除即墓碑:ChatDeleted 到达后两端都硬删除,Telegram 模式。
// ---------------------------------------------------------------------------

class SyncEngine extends pbg.SyncServiceBase {
  SyncEngine({
    required this.identity,
    required this.store,
    this.heartbeatInterval = const Duration(seconds: 15),
  });

  final Identity identity;
  final Store store;
  final Duration heartbeatInterval;

  static const _maxBackoff = Duration(seconds: 30);

  final _events = StreamController<EngineEvent>.broadcast();
  Stream<EngineEvent> get events => _events.stream;

  /// 门面层本地点火事件(不经网络)。
  void emitLocal(EngineEvent e) => _events.add(e);

  /// peerId → 该设备所有开放中的信封流(我方连出的 + 对方连入的)。
  final _sinks = <String, Set<StreamController<pb.Envelope>>>{};
  final _sessions = <String, _OutgoingSession>{};

  RendezvousClient? _rendezvous;
  StreamSubscription<RendezvousMail>? _mailSub;

  /// 挂接中转服务器(可选):离线信封经服务器邮箱兜底送达。
  /// 不挂接时行为与之前完全一致(只留 ops 表等重连补发)。
  void attachRendezvous(RendezvousClient rc) {
    _rendezvous = rc;
    // 经服务器邮箱到达的离线信封(已解密):走统一应用路径。
    _mailSub = rc.mail.listen((mail) {
      final peer = store.getPeer(mail.fromPeerId);
      if (peer == null) return;
      try {
        _handleIncoming(peer, pb.Envelope.fromBuffer(mail.envelopeBytes));
      } catch (_) {}
    });
  }

  RendezvousClient? get rendezvous => _rendezvous;

  // ------------------------------------------------------------ 公共 API

  bool isOnline(String peerId) => (_sinks[peerId]?.isNotEmpty) ?? false;

  /// 发送文本消息。
  Future<Message> sendText(String peerId, String text) async {
    final msg = await _commitMessage(peerId, (lamport, createdAt) => Message(
      msgId: const Uuid().v4(),
      convId: Store.convIdFor(identity.deviceId, peerId),
      senderId: identity.deviceId,
      lamport: lamport,
      createdAtMs: createdAt,
      kind: Message.kindText,
      text: text,
    ));
    _mirrorChat(peerId, msg);
    return msg;
  }

  /// 记录一条文件消息(由传输层调用,文件元数据已就绪)。
  Future<Message> commitFileMessage(
      String peerId, pb.ChatMessage fileMsg) async {
    final msg = await _commitMessage(peerId, (lamport, createdAt) => Message(
      msgId: fileMsg.msgId,
      convId: Store.convIdFor(identity.deviceId, peerId),
      senderId: identity.deviceId,
      lamport: lamport,
      createdAtMs: createdAt,
      kind: fileMsg.kind,
      fileId: fileMsg.fileId,
      fileName: fileMsg.fileName,
      fileSize: fileMsg.fileSize.toInt(),
      fileSha256: fileMsg.fileSha256.isEmpty ? null : fileMsg.fileSha256,
      durationMs: fileMsg.durationMs,
      fileState: Message.fileStatePending,
    ));
    _mirrorChat(peerId, msg);
    return msg;
  }

  /// 消息落库 + op 记录 + 在线推送(通用路径)。
  Future<Message> _commitMessage(
      String peerId, Message Function(int lamport, int createdAt) build) async {
    final convId = Store.convIdFor(identity.deviceId, peerId);
    store.ensureConversation(convId, peerId);
    final msg = build(store.nextLamport(convId),
        DateTime.now().millisecondsSinceEpoch);
    store.insertMessage(msg);
    store.setSendState(msg.msgId, Message.sendSending);
    final proto = _chatToProto(msg);
    final seq = store.appendOp(peerId, Op.typeMsg, proto.writeToBuffer());
    proto.opSeq = Int64(seq);
    _trackPending(peerId, seq, msg.msgId);
    _push(peerId, pb.Envelope(id: const Uuid().v4(), chat: proto));
    _events.add(MessageAdded(peerId, msg));
    return msg;
  }

  // ------------------------------------------------ 发送状态机(ACK 驱动)

  /// peerId → {opSeq → msgId}:等对端游标 ACK 的发出消息。
  final _pendingAcks = <String, Map<int, String>>{};

  void _trackPending(String peerId, int seq, String msgId) {
    _pendingAcks.putIfAbsent(peerId, () => {})[seq] = msgId;
  }

  /// 对端游标推进:seq ≤ cursor 的挂起消息 → 已送达。
  void _markDelivered(String peerId, int cursor) {
    final pend = _pendingAcks[peerId];
    if (pend == null || pend.isEmpty) return;
    final done = <String>[];
    pend.removeWhere((seq, msgId) {
      if (seq <= cursor) {
        done.add(msgId);
        return true;
      }
      return false;
    });
    for (final id in done) {
      store.setSendState(id, Message.sendOk);
      _events.add(MessageStateChanged(id));
    }
  }

  /// 标记发送失败(传输异常等)。
  void markFailed(String msgId) {
    store.setSendState(msgId, Message.sendFailed);
    _events.add(MessageStateChanged(msgId));
  }

  /// 重推一条自己发的消息(失败重发;接收方文件消息则触发重新拉取)。
  void repushMessage(Message m) {
    store.setSendState(m.msgId, Message.sendSending);
    _events.add(MessageStateChanged(m.msgId));
    final proto = _chatToProto(m);
    if (m.convId.startsWith('g:')) {
      final gid = m.convId.substring(2);
      _fanOutGroup(gid, proto..groupId = gid);
    } else {
      // 1:1:convId = 'devA:devB',取不是我的那段。
      final parts = m.convId.split(':');
      final other = (parts.length > 1 && parts.first == identity.deviceId)
          ? parts.last
          : parts.first;
      _trackPending(other, 0, m.msgId); // seq=0 立即可被任意 ACK 清
      _push(other, pb.Envelope(id: const Uuid().v4(), chat: proto));
    }
  }

  /// 多设备镜像:把发给 [peerId] 的消息同步给"我的设备"(带 conv_peer 标记)。
  void _mirrorChat(String peerId, Message msg) {
    final selfPeers = store.selfPeers();
    if (selfPeers.isEmpty) return;
    final proto = _chatToProto(msg)
      ..convPeer = peerId
      ..sender = identity.deviceId;
    for (final self in selfPeers) {
      if (self.deviceId == peerId) continue; // 对方本身就是我的设备,无需镜像
      proto.opSeq = Int64(store.appendOp(
          self.deviceId, Op.typeMsg, (proto..opSeq = Int64.ZERO).writeToBuffer()));
      _push(self.deviceId, pb.Envelope(id: const Uuid().v4(), chat: proto));
    }
  }
  /// 删除消息(Telegram 模式):本端硬删除 + 墓碑 op,对端在线即推、
  /// 不在线则重连补发。同时镜像给"我的设备"。
  Future<void> deleteMessages(String peerId, List<String> msgIds,
      {bool clearAll = false}) async {
    _doDelete(peerId, peerId, msgIds, clearAll);
    // 镜像:我的设备上删除同一个会话(conv_peer=peerId)。
    for (final self in store.selfPeers()) {
      if (self.deviceId == peerId) continue;
      _doDelete(self.deviceId, peerId, msgIds, clearAll);
    }
  }

  void _doDelete(
      String targetPeer, String convPeer, List<String> msgIds, bool clearAll) {
    final convId = Store.convIdFor(identity.deviceId, convPeer);
    if (clearAll) {
      store.clearConversation(convId);
    } else {
      store.deleteMessages(convId, msgIds);
    }
    final deleted =
        pb.ChatDeleted(msgIds: msgIds, clearAll: clearAll);
    final seq =
        store.appendOp(targetPeer, Op.typeDelete, deleted.writeToBuffer());
    // 线上消息的 conv_peer 语义 = "接收方视角下的会话对方":
    //  - 直发(target==convPeer):留空,接收方回退到信封发送者,即正确会话对方;
    //  - 镜像(target 是我的设备):填 convPeer,使其落到与我对应设备的会话。
    final wireConvPeer = targetPeer == convPeer ? '' : convPeer;
    _push(targetPeer, pb.Envelope(
      id: const Uuid().v4(),
      chatDeleted: pb.ChatDeleted(
          opSeq: Int64(seq),
          msgIds: msgIds,
          clearAll: clearAll,
          convPeer: wireConvPeer),
    ));
    _events.add(MessagesDeleted(targetPeer, msgIds, clearAll));
  }

  /// 剪贴板同步(瞬态,不落库不补发)。
  void sendClipboard(String peerId, String text) {
    _push(peerId, pb.Envelope(
      id: const Uuid().v4(),
      clipboard: pb.ClipboardSync(
          text: text, atMs: Int64(DateTime.now().millisecondsSinceEpoch)),
    ));
  }

  /// 取消文件传输信号。
  void sendFileCancel(String peerId, String fileId) {
    _push(peerId, pb.Envelope(
      id: const Uuid().v4(),
      fileCancel: pb.FileCancel(fileId: fileId),
    ));
  }

  /// 对端上线(被发现在线/已知地址变化)时调用,确保连出会话存在。
  void ensureSession(Peer peer, {String? host, int? port}) {
    final existing = _sessions[peer.deviceId];
    if (existing != null && existing.isOpen) return;
    final targetHost = host ?? peer.lastHost;
    final targetPort = port ?? peer.lastPort;
    if (targetHost == null || targetHost.isEmpty || targetPort == null) return;
    _sessions[peer.deviceId]?.dispose();
    final session = _OutgoingSession(
      engine: this,
      peer: peer,
      host: targetHost,
      port: targetPort,
    );
    _sessions[peer.deviceId] = session;
    session.start();
  }

  /// 对端地址刷新(发现层回调)。
  void notePeerAddress(Peer peer, String host, int port) {
    store.updatePeerSeen(
        peer.deviceId, host, port, DateTime.now().millisecondsSinceEpoch);
    peer.lastHost = host;
    peer.lastPort = port;
    ensureSession(peer, host: host, port: port);
  }

  /// 启动时已配对设备逐个尝试建连。
  void bootstrapSessions() {
    for (final peer in store.allPeers()) {
      ensureSession(peer);
    }
  }

  /// 对端从局域网消失(发现层超时未再出现):立即断开全部链路并标记离线。
  ///
  /// 解决的场景:对方离开后 TCP 处于半开状态,gRPC 不会立刻报错,
  /// 若不主动断开,在线状态将长期失真。对方再次出现时由发现层
  /// 回调重新建连(见 notePeerAddress)。
  void forceDisconnect(String peerId) {
    // 1) 连出会话(其 dispose 会注销 sink、关闭通道、取消重连定时器)。
    _sessions[peerId]?.dispose();
    _sessions.remove(peerId);
    // 2) 对端连入的服务端 sink:关闭即触发 handler 的 yield* 收尾与注销。
    final set = _sinks[peerId];
    final wasOnline = set != null && set.isNotEmpty;
    if (set != null) {
      for (final sink in Set.of(set)) {
        unawaited(sink.close());
      }
      _sinks.remove(peerId);
    }
    if (wasOnline) {
      _events.add(PeerStatusChanged(peerId, false));
    }
  }

  // ------------------------------------------------------------ 群聊

  /// 群定义扇出(建群/改群):全体成员 + 我的设备。
  /// [extraTargets] 追加接收方(新拉入的成员 / 被移出者,用于告知变更)。
  /// [dissolve] true 时通知成员解散并删除本地群数据。
  /// [avatarPng] 群头像(门面从 avatars/group_<id>.png 读取)。
  void broadcastGroupSync(Group group,
      {Set<String>? extraTargets,
      bool dissolve = false,
      List<int>? avatarPng}) {
    final targets = <String>{
      ...group.memberIds.where((id) => id != identity.deviceId),
      ...store.selfPeers().map((s) => s.deviceId),
      ...?extraTargets,
    };
    final avatar = (avatarPng != null && avatarPng.length <= 96 * 1024)
        ? avatarPng
        : const <int>[];
    final def = pb.GroupSync(
      groupId: group.id,
      name: group.name,
      memberIds: group.memberIds,
      createdAtMs: Int64(group.createdAtMs),
      dissolved: dissolve,
      avatarPng: avatar,
    );
    for (final target in targets) {
      store.appendOp(target, Op.typeGroup, def.writeToBuffer());
      _push(target, pb.Envelope(id: const Uuid().v4(), groupSync: def));
    }
  }

  void _applyGroupSync(String peerId, pb.GroupSync gs) {
    if (gs.groupId.isEmpty) return;
    if (gs.dissolved) {
      // 解散:删除本地群与群消息。
      if (store.getGroup(gs.groupId) != null) {
        store.deleteGroup(gs.groupId);
        _events.add(GroupSynced(gs.groupId));
      }
      return;
    }
    if (gs.memberIds.isEmpty) return;
    if (!gs.memberIds.contains(identity.deviceId)) {
      // 被移出群:删除本地群与群消息(保留 ops 供幂等)。
      if (store.getGroup(gs.groupId) != null) {
        store.deleteGroup(gs.groupId);
        _events.add(GroupSynced(gs.groupId));
      }
      return;
    }
    store.insertGroup(Group(
      id: gs.groupId,
      name: gs.name,
      createdAtMs: gs.createdAtMs.toInt(),
      memberIds: gs.memberIds,
    ));
    if (gs.avatarPng.isNotEmpty) {
      onGroupAvatar?.call(gs.groupId, gs.avatarPng);
    }
    _events.add(GroupSynced(gs.groupId));
  }

  /// 群剪贴板同步(扇出)。
  void sendGroupClipboard(String groupId, String text) {
    for (final memberId in store.groupRecipients(groupId)) {
      sendClipboard(memberId, text);
    }
  }

  /// 发送群消息:同一 msg_id 扇出给每个成员(每条链路独立 E2E 加密),
  /// 重复到达按 msg_id 幂等去重;同时镜像给自己的其他设备。
  Future<Message> sendGroupText(String groupId, String text) async {
    final convId = Group.convIdOf(groupId);
    final msg = Message(
      msgId: const Uuid().v4(),
      convId: convId,
      senderId: identity.deviceId,
      lamport: store.nextLamport(convId),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      kind: Message.kindText,
      text: text,
    );
    store.insertMessage(msg);
    _fanOutGroup(groupId, _chatToProto(msg)..groupId = groupId);
    _events.add(MessageAdded(groupId, msg));
    return msg;
  }

  /// 群文件消息(传输层调用):元数据扇出,各成员向发送者拉取文件本体。
  Future<Message> commitGroupFileMessage(
      String groupId, pb.ChatMessage fileMsg) async {
    final convId = Group.convIdOf(groupId);
    final msg = Message(
      msgId: fileMsg.msgId,
      convId: convId,
      senderId: identity.deviceId,
      lamport: store.nextLamport(convId),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      kind: fileMsg.kind,
      fileId: fileMsg.fileId,
      fileName: fileMsg.fileName,
      fileSize: fileMsg.fileSize.toInt(),
      fileSha256: fileMsg.fileSha256.isEmpty ? null : fileMsg.fileSha256,
      durationMs: fileMsg.durationMs,
      fileState: Message.fileStatePending,
    );
    store.insertMessage(msg);
    _fanOutGroup(groupId, fileMsg..groupId = groupId);
    _events.add(MessageAdded(groupId, msg));
    return msg;
  }

  void _fanOutGroup(String groupId, pb.ChatMessage proto) {
    proto
      ..sender = identity.deviceId
      ..groupId = groupId;
    final recipients = store.groupRecipients(groupId);
    var firstSeq = -1;
    for (final memberId in recipients) {
      proto.opSeq = Int64(store.appendOp(
          memberId, Op.typeMsg, (proto..opSeq = Int64.ZERO).writeToBuffer()));
      if (firstSeq < 0) firstSeq = proto.opSeq.toInt();
      _push(memberId, pb.Envelope(id: const Uuid().v4(), chat: proto));
    }
    // 发送状态:任一成员 ACK 即视为送达。
    if (firstSeq >= 0) {
      for (final memberId in recipients) {
        _trackPending(memberId, firstSeq, proto.msgId);
        break;
      }
    }
    // 镜像到我的设备(group_id 已带,接收端按群会话落地)。
    for (final self in store.selfPeers()) {
      if (recipients.contains(self.deviceId)) continue;
      proto.opSeq = Int64(store.appendOp(
          self.deviceId, Op.typeMsg, (proto..opSeq = Int64.ZERO).writeToBuffer()));
      _push(self.deviceId, pb.Envelope(id: const Uuid().v4(), chat: proto));
    }
  }

  /// 删除群消息(全体成员 + 镜像)。
  Future<void> deleteGroupMessages(String groupId, List<String> msgIds,
      {bool clearAll = false}) async {
    final convId = Group.convIdOf(groupId);
    if (clearAll) {
      store.clearConversation(convId);
    } else {
      store.deleteMessages(convId, msgIds);
    }
    final payload = pb.ChatDeleted(msgIds: msgIds, clearAll: clearAll)
      ..groupId = groupId;
    final targets = [
      ...store.groupRecipients(groupId),
      ...store.selfPeers().map((s) => s.deviceId),
    ];
    for (final target in targets) {
      final seq = store.appendOp(
          target, Op.typeDelete, (payload..opSeq = Int64.ZERO).writeToBuffer());
      _push(target, pb.Envelope(
        id: const Uuid().v4(),
        chatDeleted: pb.ChatDeleted(
            opSeq: Int64(seq),
            msgIds: msgIds,
            clearAll: clearAll,
            groupId: groupId),
      ));
    }
    _events.add(MessagesDeleted(groupId, msgIds, clearAll));
  }

  // ------------------------------------------------------ 已读回执 / 回应

  /// 标记会话已读(convKey:群 ID 或对方设备 ID)。
  /// 给会话内所有入向消息的原作者们发送 ReadReceipt;离线走 ops 补发。
  void markRead(String convKey) {
    final isGroup = store.getGroup(convKey) != null;
    final convId = isGroup
        ? Group.convIdOf(convKey)
        : Store.convIdFor(identity.deviceId, convKey);
    final unread = store.unreadIncoming(convId, identity.deviceId);
    if (unread.isEmpty) return;
    final receipt = pb.ReadReceipt(
      reader: identity.deviceId,
      msgIds: unread,
      convPeer: isGroup ? '' : convKey,
      groupId: isGroup ? convKey : '',
    );
    // 本地立刻置已读(入向语义:回执已发,避免重复回执)。
    store.markReadByIds(unread);
    final targets = isGroup ? store.groupRecipients(convKey) : [convKey];
    for (final t in targets) {
      if (t == identity.deviceId) continue;
      store.appendOp(t, Op.typeReceipt, receipt.writeToBuffer());
      _push(t, pb.Envelope(id: const Uuid().v4(), readReceipt: receipt));
    }
    // 本地点火:刷新会话未读徽标等 UI。
    _events.add(ReceiptsUpdated(convKey, unread));
  }

  /// 应用已读回执:仅命中"我(或我的设备)发出的消息"。
  void _applyReadReceipt(String peerId, pb.ReadReceipt rr) {
    if (rr.msgIds.isEmpty) return;
    final authors = <String>{
      identity.deviceId,
      ...store.selfPeers().map((s) => s.deviceId),
    };
    final changed = store.markRead(rr.msgIds, authors.toList());
    final convKey = rr.groupId.isNotEmpty
        ? rr.groupId
        : (rr.convPeer.isNotEmpty ? rr.convPeer : peerId);
    if (changed > 0) {
      _events.add(ReceiptsUpdated(convKey, rr.msgIds));
    }
    // 转发给我的其他设备(镜像副本按原作者 ID 命中,各自更新气泡)。
    for (final self in store.selfPeers()) {
      if (self.deviceId == peerId) continue;
      _push(self.deviceId,
          pb.Envelope(id: const Uuid().v4(), readReceipt: rr));
    }
  }

  /// 设置/取消表情回应(emoji 空串 = 取消自己的回应)。
  /// convKey:群 ID 或对方设备 ID。
  void setReaction(String convKey, String msgId, String emoji) {
    final isGroup = store.getGroup(convKey) != null;
    final update = pb.ReactionUpdate(
      msgId: msgId,
      groupId: isGroup ? convKey : '',
      convPeer: isGroup ? '' : convKey,
      deviceId: identity.deviceId,
      emoji: emoji,
    );
    _applyReaction(identity.deviceId, update, local: true);
    final targets = <String>{
      ...isGroup ? store.groupRecipients(convKey) : [convKey],
      ...store.selfPeers().map((s) => s.deviceId),
    };
    for (final t in targets) {
      if (t == identity.deviceId) continue;
      store.appendOp(t, Op.typeReaction, update.writeToBuffer());
      _push(t, pb.Envelope(id: const Uuid().v4(), reaction: update));
    }
  }

  void _applyReaction(String peerId, pb.ReactionUpdate ru, {bool local = false}) {
    if (ru.msgId.isEmpty || ru.deviceId.isEmpty) return;
    store.updateReaction(ru.msgId, ru.deviceId, ru.emoji);
    final convKey = ru.groupId.isNotEmpty
        ? ru.groupId
        : (ru.convPeer.isNotEmpty ? ru.convPeer : peerId);
    _events.add(ReactionsChanged(convKey, ru.msgId));
    // 转发给我的其他设备(收到他人回应时)。
    if (!local) {
      for (final self in store.selfPeers()) {
        if (self.deviceId == peerId) continue;
        _push(self.deviceId,
            pb.Envelope(id: const Uuid().v4(), reaction: ru));
      }
    }
  }

  @override
  Stream<pb.Envelope> channel(
      ServiceCall call, Stream<pb.Envelope> requestStream) async* {
    final peer = Auth.verify(call, store);
    final peerId = peer.deviceId;

    final out = StreamController<pb.Envelope>();
    _registerSink(peerId, out);

    final sub = requestStream.listen(
      (env) => _handleIncoming(peer, env),
      onError: (_) {},
      onDone: () => out.close(),
    );

    try {
      yield* out.stream;
    } finally {
      await sub.cancel();
      _unregisterSink(peerId, out);
    }
  }

  // ------------------------------------------------------------ 内部

  void _registerSink(String peerId, StreamController<pb.Envelope> sink) {
    final wasOffline = !isOnline(peerId);
    _sinks.putIfAbsent(peerId, () => {}).add(sink);
    if (wasOffline) _events.add(PeerStatusChanged(peerId, true));
    // 会话建立即互推个人资料(名称/头像),对端 UI 立即可用。
    final profile = profileProvider?.call();
    if (profile != null) {
      _push(peerId,
          pb.Envelope(id: const Uuid().v4(), profileUpdate: profile));
    }
  }

  /// 个人资料提供器(门面注入:名称 + 头像 PNG)。
  pb.ProfileUpdate? Function()? profileProvider;

  /// 收到对端资料(门面负责落盘与事件)。
  void Function(String peerId, pb.ProfileUpdate profile)? onProfileUpdate;

  /// 收到群头像(随 GroupSync 到达,门面落盘)。
  void Function(String groupId, List<int> avatarPng)? onGroupAvatar;

  /// 头像/名称变更后广播给全部已配对设备(含 op 离线补发)。
  void broadcastProfile() {
    final profile = profileProvider?.call();
    if (profile == null) return;
    final bytes = profile.writeToBuffer();
    for (final p in store.allPeers()) {
      store.appendOp(p.deviceId, Op.typeProfile, bytes);
      _push(p.deviceId,
          pb.Envelope(id: const Uuid().v4(), profileUpdate: profile));
    }
  }

  void _unregisterSink(String peerId, StreamController<pb.Envelope> sink) {
    final set = _sinks[peerId];
    if (set == null) return;
    set.remove(sink);
    if (set.isEmpty) {
      _sinks.remove(peerId);
      _events.add(PeerStatusChanged(peerId, false));
    }
  }

  void _push(String peerId, pb.Envelope env) {
    // 双路投递:幂等族信封(消息/删除/回执/回应/群定义/资料/剪贴板)在连着
    // 中转服务器时同时落一份到离线邮箱——活链路即时达,链路僵死时靠对端
    // 轮询邮箱兜底(msg_id 幂等去重,双份无害)。有状态信封(文件帧/拉取)
    // 绝不走邮箱,无活链路时丢弃,由调用方的超时/重试兜底。
    _pushLive(peerId, env);
    final rc = _rendezvous;
    if (rc != null && rc.connected && _mailboxSafe(env)) {
      unawaited(rc.pushMailbox(peerId, env.writeToBuffer()));
    }
  }

  /// 尝试经活 sink 投递;返回是否投出。
  bool _pushLive(String peerId, pb.Envelope env) {
    final set = _sinks[peerId];
    if (set == null || set.isEmpty) return false;
    // 同一设备可能有双向两条链路:每个信封只投递一条(避免有状态信封重复
    // 处理),优先最新注册的链路(对端重连后新链路后注册,旧链路拆除有竞态)。
    final sinks = set.toList();
    for (final sink in sinks.reversed) {
      try {
        sink.add(env);
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// 信封是否可安全进离线邮箱(幂等 + 尺寸可控)。
  bool _mailboxSafe(pb.Envelope env) {
    switch (env.whichPayload()) {
      case pb.Envelope_Payload.chat:
      case pb.Envelope_Payload.chatDeleted:
      case pb.Envelope_Payload.readReceipt:
      case pb.Envelope_Payload.reaction:
      case pb.Envelope_Payload.groupSync:
      case pb.Envelope_Payload.profileUpdate:
      case pb.Envelope_Payload.clipboard:
        return env.writeToBuffer().length <= 128 * 1024;
      default:
        return false;
    }
  }

  /// 处理来自对端的信封(两个方向共用)。
  void _handleIncoming(Peer peer, pb.Envelope env) {
    final peerId = peer.deviceId;
    _noteIncoming(peerId, env);
    switch (env.whichPayload()) {
      case pb.Envelope_Payload.hello:
        // 对端告知"我已应用到你的 op 第 N 条":补发 (N, +∞) 并压缩。
        final cursor = env.hello.appliedPeerSeq.toInt();
        store.setPeerAppliedSeq(peerId, cursor);
        store.compactOps(peerId, cursor);
        _markDelivered(peerId, cursor);
        _replayOps(peer, cursor);
      case pb.Envelope_Payload.chat:
        _applyChat(peer, env.chat);
      case pb.Envelope_Payload.chatDeleted:
        _applyDelete(peer, env.chatDeleted);
      case pb.Envelope_Payload.clipboard:
        _events.add(ClipboardReceived(peerId, env.clipboard.text));
      case pb.Envelope_Payload.fileCancel:
        _events.add(FileCancelled(peerId, env.fileCancel.fileId));
      case pb.Envelope_Payload.syncAck:
        final cursor = env.syncAck.appliedPeerSeq.toInt();
        store.setPeerAppliedSeq(peerId, cursor);
        store.compactOps(peerId, cursor);
        _markDelivered(peerId, cursor);
      case pb.Envelope_Payload.fileFetch:
        _events.add(FileFetchRequested(
            peerId, env.fileFetch.fileId, env.fileFetch.offset.toInt()));
      case pb.Envelope_Payload.fileData:
        _events.add(FileDataReceived(peerId, env.fileData));
      case pb.Envelope_Payload.fileDataAck:
        _events.add(FileDataAcked(peerId, env.fileDataAck.fileId,
            env.fileDataAck.ackedOffset.toInt()));
      case pb.Envelope_Payload.callOffer:
        _events.add(CallOfferReceived(peerId, env.callOffer));
      case pb.Envelope_Payload.callAnswer:
        _events.add(CallAnswerReceived(peerId, env.callAnswer));
      case pb.Envelope_Payload.callCandidate:
        _events.add(CallCandidateReceived(peerId, env.callCandidate));
      case pb.Envelope_Payload.callEnd:
        _events.add(CallEndReceived(peerId, env.callEnd));
      case pb.Envelope_Payload.groupSync:
        _applyGroupSync(peerId, env.groupSync);
      case pb.Envelope_Payload.readReceipt:
        _applyReadReceipt(peerId, env.readReceipt);
      case pb.Envelope_Payload.reaction:
        _applyReaction(peerId, env.reaction);
      case pb.Envelope_Payload.profileUpdate:
        if (env.profileUpdate.deviceName.isNotEmpty ||
            env.profileUpdate.avatarPng.isNotEmpty) {
          onProfileUpdate?.call(peerId, env.profileUpdate);
        }
      case pb.Envelope_Payload.linkAuth:
        break; // 外部链路鉴权在 attach 前由调用方完成,此处忽略
      case pb.Envelope_Payload.heartbeat:
      case pb.Envelope_Payload.fileOffer:
      case pb.Envelope_Payload.fileAnswer:
      case pb.Envelope_Payload.notSet:
        break; // 文件拉取走 TransferService,此处无需处理
    }
  }

  // ---------------------------------------------------- 外部传输链路

  /// 已 attach 的外部链路 sink → 其入向订阅(清理用)。
  final _externalSubs =
      <StreamController<pb.Envelope>, StreamSubscription<pb.Envelope>>{};

  /// 外部链路(WebRTC)活性跟踪:
  /// 对端最后一次来信时间 / 是否见过对端心跳(兼容旧版判定)/ 心跳与看门狗。
  final _lastRecvAt = <String, int>{};
  final _extHeartbeatSeen = <String, bool>{};
  Timer? _extHeartbeatTimer;
  Timer? _extWatchdogTimer;

  static const _extStaleMs = 45 * 1000; // 无来信判定僵死

  void _noteIncoming(String peerId, pb.Envelope env) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastRecvAt[peerId] = now;
    if (env.whichPayload() == pb.Envelope_Payload.heartbeat) {
      _extHeartbeatSeen[peerId] = true;
    }
  }

  void _startExtTimers() {
    _extHeartbeatTimer ??= Timer.periodic(heartbeatInterval, (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _sinks.forEach((peerId, set) {
        // 只有存在外部链路且对端也会发心跳时,才向其发送心跳/检测。
        final ext = _externalSubs.keys
            .any((s) => _sinks[peerId]?.contains(s) ?? false);
        if (!ext) return;
        _lastRecvAt.putIfAbsent(peerId, () => now);
        for (final sink in set.toList()) {
          if (!_externalSubs.containsKey(sink)) continue;
          try {
            sink.add(pb.Envelope(
              id: const Uuid().v4(),
              heartbeat:
                  pb.Heartbeat(atMs: Int64(DateTime.now().millisecondsSinceEpoch)),
            ));
          } catch (_) {}
        }
      });
    });
    _extWatchdogTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final stalePeers = <String>[];
      _sinks.forEach((peerId, set) {
        final sawHeartbeat = _extHeartbeatSeen[peerId] ?? false;
        if (!sawHeartbeat) return; // 旧版对端不发心跳:跳过判定,兼容
        final last = _lastRecvAt[peerId];
        if (last != null && now - last > _extStaleMs) {
          stalePeers.add(peerId);
        }
      });
      for (final peerId in stalePeers) {
        // 判死:强制拆除外部链路(触发重连),UI 即时转离线。
        final sinks = (_sinks[peerId] ?? const {}).toList();
        var wasOnline = (_sinks[peerId]?.isNotEmpty) ?? false;
        for (final sink in sinks) {
          final sub = _externalSubs.remove(sink);
          unawaited(sub?.cancel() ?? Future.value());
          _unregisterSink(peerId, sink);
          unawaited(sink.close());
        }
        _extHeartbeatSeen.remove(peerId);
        _lastRecvAt.remove(peerId);
        if (wasOnline) {
          _events.add(PeerStatusChanged(peerId, false));
        }
      }
    });
  }

  void _stopExtTimers() {
    _extHeartbeatTimer?.cancel();
    _extHeartbeatTimer = null;
    _extWatchdogTimer?.cancel();
    _extWatchdogTimer = null;
    _lastRecvAt.clear();
    _extHeartbeatSeen.clear();
  }

  /// 外部传输层(WebRTC DataChannel 等)注册一条到 [peerId] 的信封链路。
  ///
  /// 前置条件(调用方保证):链路已加密且对端 LinkAuth 已校验通过。
  /// 返回的 sink 用于向对端【发送】信封;[incoming] 为对端来的信封流。
  /// 注册后自动发送 Hello 触发双向 op 补发。
  StreamController<pb.Envelope> attachExternalTransport(
      String peerId, Stream<pb.Envelope> incoming) {
    final peer = store.getPeer(peerId);
    if (peer == null) {
      throw StateError('attachExternalTransport: unknown peer $peerId');
    }
    final sink = StreamController<pb.Envelope>();
    final sub = incoming.listen(
      (env) => _handleIncoming(peer, env),
      onError: (_) => detachExternalTransport(peerId, sink),
      onDone: () => detachExternalTransport(peerId, sink),
    );
    _externalSubs[sink] = sub;
    _registerSink(peerId, sink);
    _startExtTimers();
    sink.add(buildHello(peerId));
    return sink;
  }

  /// 断开并注销外部链路。
  void detachExternalTransport(
      String peerId, StreamController<pb.Envelope> sink) {
    final sub = _externalSubs.remove(sink);
    unawaited(sub?.cancel() ?? Future.value());
    _unregisterSink(peerId, sink);
    unawaited(sink.close());
  }

  /// 向指定对端发送信封(供 TransferManager 等内部模块使用)。
  void sendEnvelope(String peerId, pb.Envelope env) => _push(peerId, env);

  /// 重放本端 ops(对端重连补发)。入库时 op_seq 未知,此处按分配的
  /// seq 回填,保证对端游标能推进、ACK 能回流、ops 能压缩。
  void _replayOps(Peer peer, int sinceSeq) {
    final ops = store.opsSince(peer.deviceId, sinceSeq);
    for (final op in ops) {
      pb.Envelope env;
      if (op.type == Op.typeMsg) {
        final chat = pb.ChatMessage.fromBuffer(op.payload);
        chat.opSeq = Int64(op.seq);
        env = pb.Envelope(id: const Uuid().v4(), chat: chat);
      } else if (op.type == Op.typeGroup) {
        final gs = pb.GroupSync.fromBuffer(op.payload);
        env = pb.Envelope(id: const Uuid().v4(), groupSync: gs);
      } else if (op.type == Op.typeProfile) {
        final pu = pb.ProfileUpdate.fromBuffer(op.payload);
        env = pb.Envelope(id: const Uuid().v4(), profileUpdate: pu);
      } else if (op.type == Op.typeReaction) {
        final ru = pb.ReactionUpdate.fromBuffer(op.payload);
        env = pb.Envelope(id: const Uuid().v4(), reaction: ru);
      } else if (op.type == Op.typeReceipt) {
        final rr = pb.ReadReceipt.fromBuffer(op.payload);
        env = pb.Envelope(id: const Uuid().v4(), readReceipt: rr);
      } else {
        final del = pb.ChatDeleted.fromBuffer(op.payload);
        env = pb.Envelope(
            id: const Uuid().v4(),
            chatDeleted: pb.ChatDeleted(
              opSeq: Int64(op.seq),
              msgIds: del.msgIds,
              clearAll: del.clearAll,
              convPeer: del.convPeer,
              groupId: del.groupId,
            ));
      }
      _push(peer.deviceId, env);
    }
  }

  void _applyChat(Peer peer, pb.ChatMessage chat) {
    final peerId = peer.deviceId;
    // 原作者:镜像/群消息显式携带,普通 1:1 即信封发送者。
    final senderId = chat.sender.isEmpty ? peerId : chat.sender;

    Message msg;
    String convKey; // 事件里标识会话(群 ID 或对方设备 ID)
    if (chat.groupId.isNotEmpty) {
      // 群消息:落群会话。
      final convId = Group.convIdOf(chat.groupId);
      store.ensureConversation(convId, chat.groupId);
      convKey = chat.groupId;
      msg = Message(
        msgId: chat.msgId,
        convId: convId,
        senderId: senderId,
        lamport: chat.lamport.toInt(),
        createdAtMs: chat.createdAtMs.toInt(),
        kind: chat.kind,
        text: chat.text,
        fileId: chat.fileId.isEmpty ? null : chat.fileId,
        fileName: chat.fileName.isEmpty ? null : chat.fileName,
        fileSize: chat.fileSize == Int64.ZERO ? null : chat.fileSize.toInt(),
        fileSha256: chat.fileSha256.isEmpty ? null : chat.fileSha256,
        durationMs: chat.durationMs,
        fileState:
            Message.hasFilePayload(chat.kind) ? Message.fileStatePending : 0,
      );
    } else {
      // 多设备镜像:conv_peer 指明会话实际属于哪个对方设备。
      final convPeer = chat.convPeer.isEmpty ? peerId : chat.convPeer;
      final convId = Store.convIdFor(identity.deviceId, convPeer);
      store.ensureConversation(convId, convPeer);
      convKey = convPeer;
      msg = Message(
        msgId: chat.msgId,
        convId: convId,
        senderId: senderId,
        lamport: chat.lamport.toInt(),
        createdAtMs: chat.createdAtMs.toInt(),
        kind: chat.kind,
        text: chat.text,
        fileId: chat.fileId.isEmpty ? null : chat.fileId,
        fileName: chat.fileName.isEmpty ? null : chat.fileName,
        fileSize: chat.fileSize == Int64.ZERO ? null : chat.fileSize.toInt(),
        fileSha256: chat.fileSha256.isEmpty ? null : chat.fileSha256,
        durationMs: chat.durationMs,
        fileState:
            Message.hasFilePayload(chat.kind) ? Message.fileStatePending : 0,
      );
    }
    final isNew = store.insertMessage(msg);
    _advanceCursor(peerId, chat.opSeq);
    if (isNew) {
      _events.add(MessageAdded(convKey, msg));
      if (Message.hasFilePayload(msg.kind)) {
        // 群文件:向原作者(信封对端或显式 sender)拉取。
        _events.add(FileMessageArrived(senderId == identity.deviceId ? peerId : senderId, msg));
      }
      // 入向镜像:收到的原始消息同步给"我的设备"(带 conv_peer/group_id,
      // 镜像消息本身带标记,不再二次转发,防回环)。
      if (chat.convPeer.isEmpty &&
          chat.groupId.isEmpty &&
          !store.isSelfDevice(peerId) &&
          store.selfPeers().isNotEmpty) {
        final mirror = pb.ChatMessage(
          msgId: chat.msgId,
          lamport: chat.lamport,
          createdAtMs: chat.createdAtMs,
          kind: chat.kind,
          text: chat.text,
          fileId: chat.fileId,
          fileName: chat.fileName,
          fileSize: chat.fileSize,
          fileSha256: chat.fileSha256,
          convPeer: peerId,
          sender: senderId,
        );
        for (final self in store.selfPeers()) {
          if (self.deviceId == peerId) continue;
          mirror.opSeq = Int64(store.appendOp(self.deviceId, Op.typeMsg,
              (mirror..opSeq = Int64.ZERO).writeToBuffer()));
          _push(self.deviceId, pb.Envelope(id: const Uuid().v4(), chat: mirror));
        }
      }
      // 群消息中继:成员 C 不在线时可经其他在线成员转达——
      // 本实现所有成员两两直连,无需中继,跳过。
    }
  }

  void _applyDelete(Peer peer, pb.ChatDeleted del) {
    final peerId = peer.deviceId;
    String convKey;
    if (del.groupId.isNotEmpty) {
      convKey = del.groupId;
      final convId = Group.convIdOf(del.groupId);
      if (del.clearAll) {
        store.clearConversation(convId);
      } else {
        store.deleteMessages(convId, del.msgIds);
      }
    } else {
      final convPeer = del.convPeer.isEmpty ? peerId : del.convPeer;
      convKey = convPeer;
      final convId = Store.convIdFor(identity.deviceId, convPeer);
      if (del.clearAll) {
        store.clearConversation(convId);
      } else {
        store.deleteMessages(convId, del.msgIds);
      }
    }
    _advanceCursor(peerId, del.opSeq);
    _events.add(MessagesDeleted(convKey, del.msgIds, del.clearAll));
    // 入向删除镜像(仅原始 1:1 删除;群删除自带扇出,镜像删除不再转发)。
    if (del.convPeer.isEmpty &&
        del.groupId.isEmpty &&
        !store.isSelfDevice(peerId) &&
        store.selfPeers().isNotEmpty) {
      for (final self in store.selfPeers()) {
        if (self.deviceId == peerId) continue;
        final payload = pb.ChatDeleted(
            msgIds: del.msgIds, clearAll: del.clearAll, convPeer: peerId);
        final seq = store.appendOp(self.deviceId, Op.typeDelete,
            (payload..opSeq = Int64.ZERO).writeToBuffer());
        _push(self.deviceId, pb.Envelope(
          id: const Uuid().v4(),
          chatDeleted: pb.ChatDeleted(
              opSeq: Int64(seq),
              msgIds: del.msgIds,
              clearAll: del.clearAll,
              convPeer: peerId),
        ));
      }
    }
  }

  /// 推进"我已应用对方 op"游标并回 ACK(供对端压缩 ops)。
  void _advanceCursor(String peerId, Int64 opSeq) {
    if (opSeq == Int64.ZERO) return;
    final seq = opSeq.toInt();
    final peer = store.getPeer(peerId);
    if (peer == null || seq <= peer.myAppliedSeq) return;
    store.setMyAppliedSeq(peerId, seq);
    _push(peerId, pb.Envelope(
      id: const Uuid().v4(),
      syncAck: pb.SyncAck(appliedPeerSeq: Int64(seq)),
    ));
  }

  pb.ChatMessage _chatToProto(Message m, {int? opSeq}) => pb.ChatMessage(
        msgId: m.msgId,
        opSeq: Int64(opSeq ?? 0),
        lamport: Int64(m.lamport),
        createdAtMs: Int64(m.createdAtMs),
        kind: m.kind,
        text: m.text,
        fileId: m.fileId ?? '',
        fileName: m.fileName ?? '',
        fileSize: Int64(m.fileSize ?? 0),
        fileSha256: m.fileSha256 ?? '',
        durationMs: m.durationMs,
      );

  /// 供会话内部使用:连出通道打开时发送 Hello。
  pb.Envelope buildHello(String peerId) {
    final peer = store.getPeer(peerId);
    return pb.Envelope(
      id: const Uuid().v4(),
      hello: pb.Hello(appliedPeerSeq: Int64(peer?.myAppliedSeq ?? 0)),
    );
  }

  void registerSessionSink(String peerId, StreamController<pb.Envelope> sink) =>
      _registerSink(peerId, sink);

  void unregisterSessionSink(String peerId, StreamController<pb.Envelope> sink) =>
      _unregisterSink(peerId, sink);

  Future<void> dispose() async {
    // 1) 关闭所有连出会话(客户端侧)。
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    await _mailSub?.cancel();
    // 2) 外部链路订阅清理。
    for (final sub in _externalSubs.values) {
      unawaited(sub.cancel());
    }
    _externalSubs.clear();
    _stopExtTimers();
    _stopExtTimers();
    // 3) 关闭所有服务端入向 sink,让 channel handler 的 yield* 收尾,
    //    连接才能 finish,server.shutdown() 才不会挂起。
    for (final set in _sinks.values) {
      for (final sink in Set.of(set)) {
        unawaited(sink.close());
      }
    }
    _sinks.clear();
    await _events.close();
  }
}

// ---------------------------------------------------------------------------
// 连出会话:维持到某个可信设备的 Channel 长连接,断线指数退避重连。
// ---------------------------------------------------------------------------

class _OutgoingSession {
  _OutgoingSession({
    required this.engine,
    required this.peer,
    required this.host,
    required this.port,
  });

  final SyncEngine engine;
  final Peer peer;
  final String host;
  final int port;

  PeerChannel? _channel;
  StreamController<pb.Envelope>? _out;
  StreamSubscription<pb.Envelope>? _inSub;
  Timer? _heartbeat;
  Timer? _reconnect;
  Duration _backoff = const Duration(seconds: 1);
  bool _disposed = false;
  bool _open = false;

  bool get isOpen => _open;

  void start() => unawaited(_connect());

  Future<void> _connect() async {
    if (_disposed) return;
    _channel = PeerChannel.connect(
      host: host,
      port: port,
      pinnedFingerprint: peer.certFingerprint,
    );
    final out = StreamController<pb.Envelope>();
    _out = out;

    try {
      final client = pbg.SyncServiceClient(_channel!.channel);
      final responses = client.channel(
        out.stream,
        options: CallOptions(
          metadata: Auth.metadata(engine.identity.deviceId, peer.token),
        ),
      );
      _inSub = responses.listen(
        (env) => engine._handleIncoming(peer, env),
        onError: (Object e) => _onClosed(
            fatal: e is GrpcError && e.code == StatusCode.unauthenticated),
        onDone: () => _onClosed(),
        cancelOnError: true,
      );
      engine.registerSessionSink(peer.deviceId, out);
      out.add(engine.buildHello(peer.deviceId));
      _open = true;
      _backoff = const Duration(seconds: 1);
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(engine.heartbeatInterval, (_) {
        if (!out.isClosed) {
          out.add(pb.Envelope(
            id: const Uuid().v4(),
            heartbeat: pb.Heartbeat(
                atMs: Int64(DateTime.now().millisecondsSinceEpoch)),
          ));
        }
      });
    } catch (_) {
      _onClosed();
    }
  }

  /// 通道关闭清理。幂等。[fatal] 为 true 时(如对端已解绑)不再重连。
  void _onClosed({bool fatal = false}) {
    if (_disposed) return;
    if (fatal) _disposed = true;
    final wasOpen = _open;
    _open = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    final out = _out;
    _out = null;
    if (out != null) {
      engine.unregisterSessionSink(peer.deviceId, out);
      unawaited(out.close());
    }
    unawaited(_inSub?.cancel() ?? Future.value());
    _inSub = null;
    unawaited(_channel?.shutdown() ?? Future.value());
    _channel = null;
    if (wasOpen || !fatal) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || (_reconnect?.isActive ?? false)) return;
    _reconnect = Timer(_backoff, () {
      _backoff = _backoff * 2 > SyncEngine._maxBackoff
          ? SyncEngine._maxBackoff
          : _backoff * 2;
      unawaited(_connect());
    });
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    _open = false;
    final out = _out;
    _out = null;
    if (out != null) {
      engine.unregisterSessionSink(peer.deviceId, out);
      unawaited(out.close());
    }
    unawaited(_inSub?.cancel() ?? Future.value());
    _inSub = null;
    unawaited(_channel?.shutdown() ?? Future.value());
    _channel = null;
  }
}
