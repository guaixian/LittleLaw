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
  });

  static const kindText = 0;
  static const kindImage = 1;
  static const kindFile = 2;
  static const kindVideo = 3;

  /// 该类型是否携带文件本体(图片/文件/视频)。
  static bool hasFilePayload(int kind) =>
      kind == kindImage || kind == kindFile || kind == kindVideo;

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
}

/// 本端产生的变更操作(同步协议核心)。append-only,对端 ACK 后压缩。
class Op {
  Op({required this.seq, required this.peerId, required this.type, required this.payload});

  static const typeMsg = 'msg';
  static const typeDelete = 'delete';
  static const typeClear = 'clear';

  final int seq;
  final String peerId;
  final String type;
  final Uint8List payload; // protobuf 序列化的 ChatMessage / ChatDeleted
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
            file_id, file_name, file_size, file_sha256, file_path, file_state)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)''',
      [
        m.msgId, m.convId, m.senderId, m.lamport, m.createdAtMs, m.kind,
        m.text, m.fileId, m.fileName, m.fileSize, m.fileSha256,
        m.filePath, m.fileState,
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
      );

  /// 按 fileId 反查(传输层用于重启后找回发送源文件)。
  Message? findMessageByFileId(String fileId, {String? senderId}) {
    final rows = senderId == null
        ? _db.select('SELECT * FROM messages WHERE file_id=? LIMIT 1', [fileId])
        : _db.select(
            'SELECT * FROM messages WHERE file_id=? AND sender_id=? LIMIT 1',
            [fileId, senderId]);
    return rows.isEmpty ? null : _messageFromRow(rows.first);
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
}
