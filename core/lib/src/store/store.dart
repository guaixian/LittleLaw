import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// 已配对(可信)设备。
class Peer {
  Peer({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.certFingerprint,
    required this.token,
    this.deviceModel = '',
    this.isSelfDevice = false,
    this.lastHost,
    this.lastPort,
    required this.pairedAtMs,
    this.lastSeenMs,
    this.myAppliedSeq = 0,
    this.peerAppliedSeq = 0,
  });

  final String deviceId;
  String deviceName;
  String platform;
  String certFingerprint;
  String token; // 共享会话令牌(hex),配对时协商
  /// 机型,如 "Xiaomi 13" / "iPhone 17 Pro Max"
  String deviceModel;
  String? lastHost;
  int? lastPort;
  int pairedAtMs;
  int? lastSeenMs;

  /// 是否是"我的设备"(同一用户的其他设备,消息全量镜像)。
  bool isSelfDevice;

  /// 我已应用到本地的、来自对方 ops 的最大 seq(我发给对方的 Hello 游标)。
  int myAppliedSeq;

  /// 对方已应用的、我的 ops 的最大 seq(对方 Hello/Ack 回报,用于 ops 压缩)。
  int peerAppliedSeq;
}

/// 聊天消息(两端内容一致;file_path/file_state 为本端簿记,不同步)。
class Message {
  Message({
    required this.msgId,
    required this.convId,
    required this.senderId,
    required this.lamport,
    required this.createdAtMs,
    required this.kind,
    this.text = '',
    this.fileId,
    this.fileName,
    this.fileSize,
    this.fileSha256,
    this.filePath,
    this.fileState = 0,
    this.durationMs = 0,
    this.read = false,
    Map<String, String>? reactions,
  }) : reactions = reactions ?? {};

  static const kindText = 0;
  static const kindImage = 1;
  static const kindFile = 2;
  static const kindVideo = 3;
  static const kindVoice = 4;

  /// 该类型是否携带文件本体(图片/文件/视频/语音)。
  static bool hasFilePayload(int kind) =>
      kind == kindImage || kind == kindFile || kind == kindVideo ||
      kind == kindVoice;

  static const fileStateNone = 0;
  static const fileStatePending = 1;
  static const fileStateTransferring = 2;
  static const fileStateDone = 3;
  static const fileStateFailed = 4;

  final String msgId;
  final String convId;
  final String senderId;
  int lamport;
  int createdAtMs;
  int kind;
  String text;
  String? fileId;
  String? fileName;
  int? fileSize;
  String? fileSha256;
  String? filePath;
  int fileState;

  /// 语音时长(kind=4)。
  final int durationMs;

  /// 语义按行区分:sender=自己 → 对方已读;sender=他人 → 我已读(回执已发)。
  bool read;

  /// 表情回应:device_id → emoji。增量更新,天然可交换。
  Map<String, String> reactions;
}

/// 本端产生的变更操作(同步协议核心)。append-only,对端 ACK 后压缩。
class Op {
  Op({required this.seq, required this.peerId, required this.type, required this.payload});

  static const typeMsg = 'msg';
  static const typeDelete = 'delete';
  static const typeClear = 'clear';
  static const typeGroup = 'group';
  static const typeReaction = 'reaction';
  static const typeReceipt = 'receipt';

  final int seq;
  final String peerId;
  final String type;
  final Uint8List payload; // protobuf 序列化的 ChatMessage / ChatDeleted
}

/// 群聊。
class Group {
  Group({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.memberIds,
  });

  final String id;
  String name;
  final int createdAtMs;
  final List<String> memberIds; // 全部成员设备 ID(含创建者本机)

  /// 会话 ID(消息表用)。
  static String convIdOf(String groupId) => 'g:$groupId';
}

/// 会话摘要(最近会话列表)。
class ConvSummary {
  ConvSummary({
    required this.convId,
    required this.kind,
    required this.text,
    required this.fileName,
    required this.atMs,
    required this.senderId,
    required this.unread,
  });

  final String convId; // 'g:<id>' 或 'devA:devB'
  final int kind; // 最后一条消息类型
  final String text;
  final String? fileName;
  final int atMs;
  final String senderId;
  final int unread;
}

/// SQLite 持久层。同步协议见 sync_engine.dart。
class Store {
  late final Database _db;

  void open(String path) {
    _db = sqlite3.open(path);
    _db.execute('PRAGMA journal_mode=WAL;');
    _db.execute('PRAGMA foreign_keys=ON;');
    _migrate();
  }

  void dispose() => _db.close();

  /// WAL 落盘压缩(备份前调用,保证 littlelaw.db 单文件完整)。
  void checkpoint() => _db.execute('PRAGMA wal_checkpoint(TRUNCATE);');

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        device_id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL,
        platform TEXT NOT NULL,
        cert_fingerprint TEXT NOT NULL,
        token TEXT NOT NULL,
        device_model TEXT NOT NULL DEFAULT '',
        is_self INTEGER NOT NULL DEFAULT 0,
        last_host TEXT,
        last_port INTEGER,
        paired_at_ms INTEGER NOT NULL,
        last_seen_ms INTEGER,
        my_applied_seq INTEGER NOT NULL DEFAULT 0,
        peer_applied_seq INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS conversations (
        conv_id TEXT PRIMARY KEY,
        peer_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS messages (
        msg_id TEXT PRIMARY KEY,
        conv_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        lamport INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        kind INTEGER NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        file_id TEXT,
        file_name TEXT,
        file_size INTEGER,
        file_sha256 TEXT,
        file_path TEXT,
        file_state INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_messages_conv
        ON messages(conv_id, lamport, msg_id);
      CREATE INDEX IF NOT EXISTS idx_messages_file
        ON messages(file_id);

      CREATE TABLE IF NOT EXISTS ops (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        payload BLOB NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_ops_peer ON ops(peer_id, seq);

      CREATE TABLE IF NOT EXISTS groups (
        group_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS group_members (
        group_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        PRIMARY KEY (group_id, device_id)
      );
    ''');
    // 轻量迁移:老库补列(已存在则忽略报错)。
    try {
      _db.execute('ALTER TABLE messages ADD COLUMN file_sha256 TEXT');
    } catch (_) {}
    try {
      _db.execute(
          "ALTER TABLE peers ADD COLUMN device_model TEXT NOT NULL DEFAULT ''");
    } catch (_) {}
    try {
      _db.execute("ALTER TABLE peers ADD COLUMN is_self INTEGER NOT NULL DEFAULT 0");
    } catch (_) {}
    try {
      _db.execute(
          'ALTER TABLE messages ADD COLUMN duration_ms INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE messages ADD COLUMN read INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
    try {
      _db.execute(
          "ALTER TABLE messages ADD COLUMN reactions TEXT NOT NULL DEFAULT '{}'");
    } catch (_) {}
  }

  /// 1:1 会话 ID:两个设备 ID 排序拼接,两端计算结果一致。
  static String convIdFor(String deviceA, String deviceB) {
    final parts = [deviceA, deviceB]..sort();
    return '${parts[0]}:${parts[1]}';
  }

  // ------------------------------------------------------------------ peers

  void upsertPeer(Peer p) {
    _db.execute(
      '''INSERT INTO peers (device_id, device_name, platform, cert_fingerprint,
           token, device_model, is_self, last_host, last_port, paired_at_ms, last_seen_ms,
           my_applied_seq, peer_applied_seq)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(device_id) DO UPDATE SET
           device_name=excluded.device_name,
           platform=excluded.platform,
           cert_fingerprint=excluded.cert_fingerprint,
           token=excluded.token,
           device_model=excluded.device_model,
           is_self=excluded.is_self''',
      [
        p.deviceId, p.deviceName, p.platform, p.certFingerprint, p.token,
        p.deviceModel, p.isSelfDevice ? 1 : 0, p.lastHost, p.lastPort,
        p.pairedAtMs, p.lastSeenMs, p.myAppliedSeq, p.peerAppliedSeq,
      ],
    );
  }

  /// 标记/取消"我的设备"(只改标记,不动信任关系)。
  void setSelfDevice(String deviceId, bool isSelf) {
    _db.execute('UPDATE peers SET is_self=? WHERE device_id=?',
        [isSelf ? 1 : 0, deviceId]);
  }

  /// 全部"我的设备"。
  List<Peer> selfPeers() =>
      _db.select('SELECT * FROM peers WHERE is_self=1').map(_peerFromRow).toList();

  bool isSelfDevice(String deviceId) {
    final rows = _db.select(
        'SELECT is_self FROM peers WHERE device_id=?', [deviceId]);
    return rows.isNotEmpty && (rows.first['is_self'] as int) == 1;
  }

  Peer? getPeer(String deviceId) {
    final rows = _db.select('SELECT * FROM peers WHERE device_id=?', [deviceId]);
    return rows.isEmpty ? null : _peerFromRow(rows.first);
  }

  List<Peer> allPeers() =>
      _db.select('SELECT * FROM peers').map(_peerFromRow).toList();

  void removePeer(String deviceId) {
    _db.execute('DELETE FROM peers WHERE device_id=?', [deviceId]);
  }

  void updatePeerSeen(String deviceId, String host, int port, int atMs) {
    _db.execute(
      'UPDATE peers SET last_host=?, last_port=?, last_seen_ms=? WHERE device_id=?',
      [host, port, atMs, deviceId],
    );
  }

  void setMyAppliedSeq(String deviceId, int seq) {
    _db.execute('UPDATE peers SET my_applied_seq=? WHERE device_id=?',
        [seq, deviceId]);
  }

  void setPeerAppliedSeq(String deviceId, int seq) {
    _db.execute(
        'UPDATE peers SET peer_applied_seq=? WHERE device_id=?', [seq, deviceId]);
  }

  Peer _peerFromRow(Row r) => Peer(
        deviceId: r['device_id'] as String,
        deviceName: r['device_name'] as String,
        platform: r['platform'] as String,
        certFingerprint: r['cert_fingerprint'] as String,
        token: r['token'] as String,
        deviceModel: (r['device_model'] as String?) ?? '',
        isSelfDevice: (r['is_self'] as int? ?? 0) == 1,
        lastHost: r['last_host'] as String?,
        lastPort: r['last_port'] as int?,
        pairedAtMs: r['paired_at_ms'] as int,
        lastSeenMs: r['last_seen_ms'] as int?,
        myAppliedSeq: r['my_applied_seq'] as int,
        peerAppliedSeq: r['peer_applied_seq'] as int,
      );

  // ---------------------------------------------------------- conversations

  void ensureConversation(String convId, String peerId) {
    _db.execute(
      'INSERT OR IGNORE INTO conversations (conv_id, peer_id, created_at_ms) VALUES (?,?,?)',
      [convId, peerId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  // -------------------------------------------------------------- messages

  /// 幂等写入(INSERT OR IGNORE)。返回 true 表示是新消息。
  bool insertMessage(Message m) {
    _db.execute(
      '''INSERT OR IGNORE INTO messages
           (msg_id, conv_id, sender_id, lamport, created_at_ms, kind, text,
            file_id, file_name, file_size, file_sha256, file_path, file_state,
            duration_ms, read, reactions)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
      [
        m.msgId, m.convId, m.senderId, m.lamport, m.createdAtMs, m.kind,
        m.text, m.fileId, m.fileName, m.fileSize, m.fileSha256,
        m.filePath, m.fileState, m.durationMs, m.read ? 1 : 0,
        jsonEncode(m.reactions),
      ],
    );
    return _db.updatedRows > 0;
  }

  Message? getMessage(String msgId) {
    final rows =
        _db.select('SELECT * FROM messages WHERE msg_id=?', [msgId]);
    return rows.isEmpty ? null : _messageFromRow(rows.first);
  }

  List<Message> listMessages(String convId, {int limit = 200, int? beforeLamport}) {
    final rows = beforeLamport == null
        ? _db.select(
            'SELECT * FROM messages WHERE conv_id=? ORDER BY lamport DESC, msg_id DESC LIMIT ?',
            [convId, limit])
        : _db.select(
            'SELECT * FROM messages WHERE conv_id=? AND lamport<? ORDER BY lamport DESC, msg_id DESC LIMIT ?',
            [convId, beforeLamport, limit]);
    return rows.map(_messageFromRow).toList().reversed.toList();
  }

  void deleteMessages(String convId, List<String> msgIds) {
    if (msgIds.isEmpty) return;
    final marks = List.filled(msgIds.length, '?').join(',');
    _db.execute(
      'DELETE FROM messages WHERE conv_id=? AND msg_id IN ($marks)',
      [convId, ...msgIds],
    );
  }

  void clearConversation(String convId) {
    _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
  }

  void updateFileState(String msgId, int state, {String? filePath}) {
    if (filePath != null) {
      _db.execute('UPDATE messages SET file_state=?, file_path=? WHERE msg_id=?',
          [state, filePath, msgId]);
    } else {
      _db.execute(
          'UPDATE messages SET file_state=? WHERE msg_id=?', [state, msgId]);
    }
  }

  /// 会话内下一条消息的 Lamport 时钟值。
  int nextLamport(String convId) {
    final rows = _db.select(
        'SELECT COALESCE(MAX(lamport), 0) AS m FROM messages WHERE conv_id=?',
        [convId]);
    return (rows.first['m'] as int) + 1;
  }

  Message _messageFromRow(Row r) => Message(
        msgId: r['msg_id'] as String,
        convId: r['conv_id'] as String,
        senderId: r['sender_id'] as String,
        lamport: r['lamport'] as int,
        createdAtMs: r['created_at_ms'] as int,
        kind: r['kind'] as int,
        text: r['text'] as String,
        fileId: r['file_id'] as String?,
        fileName: r['file_name'] as String?,
        fileSize: r['file_size'] as int?,
        fileSha256: r['file_sha256'] as String?,
        filePath: r['file_path'] as String?,
        fileState: r['file_state'] as int,
        durationMs: (r['duration_ms'] as int? ?? 0),
        read: ((r['read'] as int? ?? 0) == 1),
        reactions: _decodeReactions(r['reactions'] as String?),
      );

  static Map<String, String> _decodeReactions(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    return {};
  }

  // ------------------------------------------------------ 回执 / 回应 / 搜索

  /// 会话内未回执的入向消息 ID(发送已读回执的依据)。
  List<String> unreadIncoming(String convId, String myDeviceId) => _db
      .select(
          'SELECT msg_id FROM messages WHERE conv_id=? AND sender_id<>? AND read=0',
          [convId, myDeviceId])
      .map((r) => r['msg_id'] as String)
      .toList();

  /// 置已读标记(仅命中 [authors] 里的设备发的消息;镜像副本按原作者命中)。
  int markRead(List<String> msgIds, List<String> authors) {
    if (msgIds.isEmpty || authors.isEmpty) return 0;
    final idMarks = List.filled(msgIds.length, '?').join(',');
    final authorMarks = List.filled(authors.length, '?').join(',');
    _db.execute(
      'UPDATE messages SET read=1 WHERE msg_id IN ($idMarks) AND sender_id IN ($authorMarks)',
      [...msgIds, ...authors],
    );
    return _db.updatedRows;
  }

  /// 按 msg_id 无条件置已读(本地"我已读"语义:入向消息,防重复回执)。
  int markReadByIds(List<String> msgIds) {
    if (msgIds.isEmpty) return 0;
    final marks = List.filled(msgIds.length, '?').join(',');
    _db.execute(
        'UPDATE messages SET read=1 WHERE msg_id IN ($marks)', msgIds);
    return _db.updatedRows;
  }

  /// 增量更新表情回复(JSON 合并,单设备单 emoji)。
  void updateReaction(String msgId, String deviceId, String emoji) {
    final rows = _db
        .select('SELECT reactions FROM messages WHERE msg_id=?', [msgId]);
    if (rows.isEmpty) return;
    final map = _decodeReactions(rows.first['reactions'] as String?);
    if (emoji.isEmpty) {
      map.remove(deviceId);
    } else {
      if (map[deviceId] == emoji) return; // 幂等
      map[deviceId] = emoji;
    }
    _db.execute('UPDATE messages SET reactions=? WHERE msg_id=?',
        [jsonEncode(map), msgId]);
  }

  /// 全库消息搜索(文本 + 文件名 LIKE,已转义)。
  List<Message> searchMessages(String query, {int limit = 200}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final esc = q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final like = '%$esc%';
    return _db
        .select(
            r"""SELECT * FROM messages
                WHERE text LIKE ? ESCAPE '\' OR file_name LIKE ? ESCAPE '\'
                ORDER BY created_at_ms DESC LIMIT ?""",
            [like, like, limit])
        .map(_messageFromRow)
        .toList();
  }

  /// 按 fileId 反查(传输层用于重启后找回发送源文件)。
  Message? findMessageByFileId(String fileId, {String? senderId}) {
    final rows = senderId == null
        ? _db.select('SELECT * FROM messages WHERE file_id=? LIMIT 1', [fileId])
        : _db.select(
            'SELECT * FROM messages WHERE file_id=? AND sender_id=? LIMIT 1',
            [fileId, senderId]);
    return rows.isEmpty ? null : _messageFromRow(rows.first);
  }

  /// 会话摘要(桌面/最近会话列表):每会话最后一条 + 未读数。
  List<ConvSummary> conversationSummaries(String myDeviceId) {
    final rows = _db.select('''
      SELECT m.conv_id, m.kind, m.text, m.file_name, m.created_at_ms, m.sender_id
      FROM messages m
      WHERE m.lamport = (
        SELECT MAX(l2.lamport) FROM messages l2 WHERE l2.conv_id = m.conv_id
      )
    ''');
    final unread = <String, int>{};
    for (final r in _db.select(
        'SELECT conv_id, COUNT(*) AS c FROM messages '
        'WHERE sender_id<>? AND read=0 GROUP BY conv_id',
        [myDeviceId])) {
      unread[r['conv_id'] as String] = r['c'] as int;
    }
    final out = rows.map((r) => ConvSummary(
          convId: r['conv_id'] as String,
          kind: r['kind'] as int,
          text: r['text'] as String,
          fileName: r['file_name'] as String?,
          atMs: r['created_at_ms'] as int,
          senderId: r['sender_id'] as String,
          unread: unread[r['conv_id'] as String] ?? 0,
        )).toList();
    out.sort((a, b) => b.atMs.compareTo(a.atMs));
    return out;
  }

  // ------------------------------------------------------------------- ops

  /// 追加 op,返回分配的 seq。调用方需在同一逻辑单元内先写业务表。
  int appendOp(String peerId, String type, Uint8List payload) {
    _db.execute('INSERT INTO ops (peer_id, type, payload) VALUES (?,?,?)',
        [peerId, type, payload]);
    final rows = _db.select('SELECT last_insert_rowid() AS s');
    return rows.first['s'] as int;
  }

  /// 对端游标之后的全部 op(重连补发)。
  List<Op> opsSince(String peerId, int seq) {
    final rows = _db.select(
        'SELECT * FROM ops WHERE peer_id=? AND seq>? ORDER BY seq ASC',
        [peerId, seq]);
    return rows
        .map((r) => Op(
              seq: r['seq'] as int,
              peerId: r['peer_id'] as String,
              type: r['type'] as String,
              payload: r['payload'] as Uint8List,
            ))
        .toList();
  }

  /// 对端已 ACK 的 op 压缩清理。
  void compactOps(String peerId, int ackedSeq) {
    _db.execute('DELETE FROM ops WHERE peer_id=? AND seq<=?', [peerId, ackedSeq]);
  }

  // ---------------------------------------------------------------- groups

  void insertGroup(Group g) {
    _db.execute('INSERT OR REPLACE INTO groups (group_id, name, created_at_ms) VALUES (?,?,?)',
        [g.id, g.name, g.createdAtMs]);
    _db.execute('DELETE FROM group_members WHERE group_id=?', [g.id]);
    for (final m in g.memberIds) {
      _db.execute('INSERT OR IGNORE INTO group_members (group_id, device_id) VALUES (?,?)',
          [g.id, m]);
    }
  }

  List<Group> allGroups() {
    final rows = _db.select('SELECT * FROM groups ORDER BY created_at_ms DESC');
    return rows.map((r) {
      final gid = r['group_id'] as String;
      final members = _db
          .select('SELECT device_id FROM group_members WHERE group_id=?', [gid])
          .map((m) => m['device_id'] as String)
          .toList();
      return Group(
        id: gid,
        name: r['name'] as String,
        createdAtMs: r['created_at_ms'] as int,
        memberIds: members,
      );
    }).toList();
  }

  Group? getGroup(String groupId) {
    final rows = _db.select('SELECT * FROM groups WHERE group_id=?', [groupId]);
    if (rows.isEmpty) return null;
    final members = _db
        .select('SELECT device_id FROM group_members WHERE group_id=?', [groupId])
        .map((m) => m['device_id'] as String)
        .toList();
    final r = rows.first;
    return Group(
      id: groupId,
      name: r['name'] as String,
      createdAtMs: r['created_at_ms'] as int,
      memberIds: members,
    );
  }

  /// 删除群定义 + 群成员表 + 群会话与消息(被移出/解散/自解散)。
  /// [keepMessages] 退群自删时保留历史。
  void deleteGroup(String groupId, {bool keepMessages = false}) {
    final convId = Group.convIdOf(groupId);
    _db.execute('DELETE FROM groups WHERE group_id=?', [groupId]);
    _db.execute('DELETE FROM group_members WHERE group_id=?', [groupId]);
    if (!keepMessages) {
      _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
      _db.execute('DELETE FROM conversations WHERE conv_id=?', [convId]);
      _db.execute('DELETE FROM ops WHERE peer_id=?', [groupId]);
    }
  }

  /// 群成员(不含本机)。
  List<String> groupRecipients(String groupId) {
    final g = getGroup(groupId);
    if (g == null) return const [];
    return g.memberIds.where((id) => id != _dbSelfId).toList();
  }

  late String _dbSelfId;

  /// 引擎启动时注入本机设备 ID(群收件人过滤用)。
  set selfDeviceId(String id) => _dbSelfId = id;
}
