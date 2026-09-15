import 'dart:convert';
import 'dart:math' as math;
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
    this.certDerBase64 = '',
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

  /// 对端证书 DER(base64)。E2E 密钥派生(ECDH)与配对确认验签用;
  /// 老数据可能为空。
  String certDerBase64;

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
    this.sendState = 0,
  }) : reactions = reactions ?? {};

  static const kindText = 0;
  static const kindImage = 1;
  static const kindFile = 2;
  static const kindVideo = 3;
  static const kindVoice = 4;
  static const kindSystem = 5; // 本地系统提示(解绑墓碑等,不同步)

  /// 该类型是否携带文件本体(图片/文件/视频/语音)。
  static bool hasFilePayload(int kind) =>
      kind == kindImage || kind == kindFile || kind == kindVideo ||
      kind == kindVoice;

  static const fileStateNone = 0;
  static const fileStatePending = 1;
  static const fileStateTransferring = 2;
  static const fileStateDone = 3;
  static const fileStateFailed = 4;

  /// 本端发送状态(仅自己发的消息,不同步):
  /// 0=已送达 1=发送中 2=失败(终态) 3=已入队待投递(离线存储转发)。
  static const sendOk = 0;
  static const sendSending = 1;
  static const sendFailed = 2;
  static const sendQueued = 3;

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

  /// 本端发送状态(sendOk/sendSending/sendFailed)。
  int sendState;

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
  static const typeProfile = 'profile';
  static const typeNoop = 'noop'; // 过期墓碑占位:让对端游标可推进

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

  /// 显式事务包裹(包内抛错自动回滚)。
  T _tx<T>(T Function() body) {
    _db.execute('BEGIN');
    try {
      final r = body();
      _db.execute('COMMIT');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

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
      CREATE TABLE IF NOT EXISTS unpair_outbox (
        device_id TEXT PRIMARY KEY,
        cert_fingerprint TEXT NOT NULL,
        token TEXT NOT NULL,
        created_ms INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS lamport_watermarks (
        conv_id TEXT PRIMARY KEY,
        next INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS deleted_msgs (
        msg_id TEXT PRIMARY KEY,
        at_ms INTEGER NOT NULL
      );
    ''');
    // 轻量迁移:老库补列(已存在则忽略报错)。
    // 整个回填包在一个事务里:崩溃时整体回滚,不会留下 pseq=0 的 op
    // 导致永不重放(丢数据)。
    _db.execute('BEGIN');
    try {
      final cols = <String, Set<String>>{};
      Set<String> colsOf(String table) => cols.putIfAbsent(
          table,
          () => _db
              .select('PRAGMA table_info($table)')
              .map((r) => r['name'] as String)
              .toSet());
      void addCol(String table, String ddl, String col) {
        if (!colsOf(table).contains(col)) {
          _db.execute(ddl);
          cols[table] = {...colsOf(table), col};
        }
      }

      addCol('messages', 'ALTER TABLE messages ADD COLUMN file_sha256 TEXT',
          'file_sha256');
      addCol('peers',
          "ALTER TABLE peers ADD COLUMN device_model TEXT NOT NULL DEFAULT ''",
          'device_model');
      addCol('peers',
          'ALTER TABLE peers ADD COLUMN is_self INTEGER NOT NULL DEFAULT 0',
          'is_self');
      addCol('messages',
          'ALTER TABLE messages ADD COLUMN duration_ms INTEGER NOT NULL DEFAULT 0',
          'duration_ms');
      addCol('messages',
          'ALTER TABLE messages ADD COLUMN read INTEGER NOT NULL DEFAULT 0',
          'read');
      addCol('messages',
          "ALTER TABLE messages ADD COLUMN reactions TEXT NOT NULL DEFAULT '{}'",
          'reactions');
      addCol('messages',
          'ALTER TABLE messages ADD COLUMN send_state INTEGER NOT NULL DEFAULT 0',
          'send_state');
      addCol('ops',
          'ALTER TABLE ops ADD COLUMN created_ms INTEGER NOT NULL DEFAULT 0',
          'created_ms');
      // per-peer 序号列:连续游标协议要求每个对端的 op 序号独立连续,
      // 全局 rowid 会让对端只看到全局序号的子集(天然空洞)。
      if (!colsOf('ops').contains('pseq')) {
        _db.execute('ALTER TABLE ops ADD COLUMN pseq INTEGER NOT NULL DEFAULT 0');
        final rows = _db.select('SELECT seq, peer_id FROM ops ORDER BY seq ASC');
        final counters = <String, int>{};
        final stmt = _db.prepare('UPDATE ops SET pseq=? WHERE seq=?');
        for (final r in rows) {
          final pid = r['peer_id'] as String;
          final n = (counters[pid] ?? 0) + 1;
          counters[pid] = n;
          stmt.execute([n, r['seq']]);
        }
        stmt.close();
      }
      // per-peer 单调序号计数器:压缩删除旧行后 MAX(pseq)+1 会复用已确认
      // 序号(离线消息拿到小号,对端游标已越过 → 永不重放),必须持久单调。
      if (!colsOf('peers').contains('next_op_seq')) {
        _db.execute(
            'ALTER TABLE peers ADD COLUMN next_op_seq INTEGER NOT NULL DEFAULT 0');
        // 初始化为各 peer 当前最大 pseq(老库回填)。
        final rows = _db.select(
            'SELECT peer_id, MAX(pseq) AS m FROM ops GROUP BY peer_id');
        for (final r in rows) {
          _db.execute('UPDATE peers SET next_op_seq=? WHERE device_id=?',
              [r['m'] as int, r['peer_id']]);
        }
      }
      addCol('peers', "ALTER TABLE peers ADD COLUMN cert_der TEXT NOT NULL DEFAULT ''",
          'cert_der');
      addCol('peers',
          'ALTER TABLE peers ADD COLUMN pending_unpair INTEGER NOT NULL DEFAULT 0',
          'pending_unpair');
      // ops (peer_id, pseq) 唯一:先清掉历史重复行再建唯一索引。
      _db.execute(
          'DELETE FROM ops WHERE seq NOT IN (SELECT MAX(seq) FROM ops GROUP BY peer_id, pseq)');
      _db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_ops_peer_pseq ON ops(peer_id, pseq)');
      // 墓碑过期清理(与 deleteOpTtlMs 同生命周期:超过该窗口的对端
      // 反正收不到删除通知了,迟到的重复投递不会再发生)。
      _db.execute('DELETE FROM deleted_msgs WHERE at_ms < ?',
          [DateTime.now().millisecondsSinceEpoch - deleteOpTtlMs]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
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
           my_applied_seq, peer_applied_seq, cert_der)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(device_id) DO UPDATE SET
           device_name=excluded.device_name,
           platform=excluded.platform,
           cert_fingerprint=excluded.cert_fingerprint,
           token=excluded.token,
           device_model=excluded.device_model,
           is_self=CASE WHEN excluded.is_self=1 THEN 1 ELSE peers.is_self END,
           cert_der=CASE WHEN excluded.cert_der='' THEN peers.cert_der ELSE excluded.cert_der END''',
      [
        p.deviceId, p.deviceName, p.platform, p.certFingerprint, p.token,
        p.deviceModel, p.isSelfDevice ? 1 : 0, p.lastHost, p.lastPort,
        p.pairedAtMs, p.lastSeenMs, p.myAppliedSeq, p.peerAppliedSeq,
        p.certDerBase64,
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

  /// 对端资料同步里的名称更新(仅展示名,不动信任关系)。
  void updatePeerName(String deviceId, String name) {
    if (name.isEmpty) return;
    _db.execute('UPDATE peers SET device_name=? WHERE device_id=?',
        [name, deviceId]);
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
        lastPort: (r['last_port'] as int?),
        pairedAtMs: r['paired_at_ms'] as int,
        lastSeenMs: r['last_seen_ms'] as int?,
        myAppliedSeq: r['my_applied_seq'] as int,
        peerAppliedSeq: r['peer_applied_seq'] as int,
        certDerBase64: (r['cert_der'] as String?) ?? '',
      );

  // ---------------------------------------------------------- conversations

  void ensureConversation(String convId, String peerId) {
    _db.execute(
      'INSERT OR IGNORE INTO conversations (conv_id, peer_id, created_at_ms) VALUES (?,?,?)',
      [convId, peerId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  // -------------------------------------------------------------- messages

  /// 幂等写入(INSERT OR IGNORE;墓碑优先)。返回 true 表示是新消息。
  /// 已被删除过的消息(墓碑在案)不再复活:双链路场景下,一条链路
  /// 拥塞中的迟到投递会晚于另一条链路上的删除到达,没有墓碑时
  /// INSERT OR IGNORE 会把已删除的消息重新插回来。
  bool insertMessage(Message m) {
    final tomb = _db.select(
        'SELECT 1 FROM deleted_msgs WHERE msg_id=? LIMIT 1', [m.msgId]);
    if (tomb.isNotEmpty) return false;
    _db.execute(
      '''INSERT OR IGNORE INTO messages
           (msg_id, conv_id, sender_id, lamport, created_at_ms, kind, text,
            file_id, file_name, file_size, file_sha256, file_path, file_state,
            duration_ms, read, reactions, send_state)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
      [
        m.msgId, m.convId, m.senderId, m.lamport, m.createdAtMs, m.kind,
        m.text, m.fileId, m.fileName, m.fileSize, m.fileSha256,
        m.filePath, m.fileState, m.durationMs, m.read ? 1 : 0,
        jsonEncode(m.reactions), m.sendState,
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
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final batch in _chunks(msgIds, 500)) {
      final marks = List.filled(batch.length, '?').join(',');
      _tx(() {
        _db.execute(
          'DELETE FROM messages WHERE conv_id=? AND msg_id IN ($marks)',
          [convId, ...batch],
        );
        final stmt = _db.prepare(
            'INSERT OR REPLACE INTO deleted_msgs (msg_id, at_ms) VALUES (?,?)');
        for (final id in batch) {
          stmt.execute([id, now]);
        }
        stmt.close();
      });
    }
  }

  /// 清空会话消息。[removeConversation] 同时删除会话行(解绑/删会话场景);
  /// 默认保留会话行(普通"清空消息"场景),避免孤儿/墓碑误删。
  /// 全部消息进墓碑表,防迟到重投复活。
  void clearConversation(String convId, {bool removeConversation = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _tx(() {
      final ids = _db
          .select('SELECT msg_id FROM messages WHERE conv_id=?', [convId])
          .map((r) => r['msg_id'] as String)
          .toList();
      _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
      final stmt = _db.prepare(
          'INSERT OR REPLACE INTO deleted_msgs (msg_id, at_ms) VALUES (?,?)');
      for (final id in ids) {
        stmt.execute([id, now]);
      }
      stmt.close();
      if (removeConversation) {
        _db.execute('DELETE FROM conversations WHERE conv_id=?', [convId]);
      }
    });
  }

  /// 彻底删除会话(消息 + 会话行 + 该会话墓碑;墓碑"清除"按钮用)。
  void deleteConversation(String convId) {
    _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
    _db.execute('DELETE FROM conversations WHERE conv_id=?', [convId]);
    _db.execute('DELETE FROM lamport_watermarks WHERE conv_id=?', [convId]);
  }

  /// 清除会话内的解绑墓碑系统消息:重新配对成功时调用——旧墓碑
  /// "已与 X 解除配对…"残留会在新会话顶部冒出,误导用户。
  void purgeTombstones(String convId) {
    _db.execute('DELETE FROM messages WHERE conv_id=? AND kind=?',
        [convId, Message.kindSystem]);
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

  void setSendState(String msgId, int state) {
    _db.execute('UPDATE messages SET send_state=? WHERE msg_id=?',
        [state, msgId]);
  }

  /// 会话内下一条消息的 Lamport 时钟值。
  ///
  /// 分配值 = max(持久水位, 库内 MAX(lamport)+1):
  ///  - 水位(≥ 已分配值)防"删除最高位消息后取 MAX 回退复用旧号";
  ///  - 取 MAX+1 兜住【对端/镜像消息带来的更高号】——双方各自独立
  ///    分配 lamport,若只看本机水位,本地新消息会拿到旧号,
  ///    排序时插进历史中间(发送顺序错乱的根因)。
  int nextLamport(String convId) {
    return _tx(() {
      final maxRows = _db.select(
          'SELECT COALESCE(MAX(lamport), 0) AS m FROM messages WHERE conv_id=?',
          [convId]);
      var next = (maxRows.first['m'] as int) + 1;
      final rows = _db.select(
          'SELECT next FROM lamport_watermarks WHERE conv_id=?', [convId]);
      if (rows.isNotEmpty) {
        final w = rows.first['next'] as int;
        if (w > next) next = w;
      }
      if (rows.isEmpty) {
        _db.execute(
            'INSERT INTO lamport_watermarks (conv_id, next) VALUES (?,?)',
            [convId, next + 1]);
      } else {
        _db.execute(
            'UPDATE lamport_watermarks SET next=? WHERE conv_id=?',
            [next + 1, convId]);
      }
      return next;
    });
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
        sendState: (r['send_state'] as int? ?? 0),
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
    var updated = 0;
    for (final idBatch in _chunks(msgIds, 500)) {
      for (final authorBatch in _chunks(authors, 500)) {
        final idMarks = List.filled(idBatch.length, '?').join(',');
        final authorMarks = List.filled(authorBatch.length, '?').join(',');
        _db.execute(
          'UPDATE messages SET read=1 WHERE msg_id IN ($idMarks) AND sender_id IN ($authorMarks)',
          [...idBatch, ...authorBatch],
        );
        updated += _db.updatedRows;
      }
    }
    return updated;
  }

  /// 按 msg_id 无条件置已读(本地"我已读"语义:入向消息,防重复回执)。
  int markReadByIds(List<String> msgIds) {
    if (msgIds.isEmpty) return 0;
    var updated = 0;
    for (final batch in _chunks(msgIds, 500)) {
      final marks = List.filled(batch.length, '?').join(',');
      _db.execute(
          'UPDATE messages SET read=1 WHERE msg_id IN ($marks)', batch);
      updated += _db.updatedRows;
    }
    return updated;
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
  /// 用 GROUP BY + MAX(lamport)(SQLite 的 max 裸列语义:取 max 所在行),
  /// lamport 并列时也只返回每会话一行,不会出现重复条目。
  List<ConvSummary> conversationSummaries(String myDeviceId) {
    final rows = _db.select('''
      SELECT m.conv_id, m.kind, m.text, m.file_name, m.created_at_ms, m.sender_id,
             MAX(m.lamport)
      FROM messages m GROUP BY m.conv_id
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

  /// 追加 op,返回分配的【per-peer 单调】seq。调用方需在同一逻辑单元内先写业务表。
  /// 序号来自 peers.next_op_seq(持久自增),与 ops 行是否已被压缩无关。
  ///
  /// 三条语句包在同一事务内:崩溃不会"烧掉"序号留下永久空洞
  /// (空洞会让对端连续游标卡死)。peer 行不存在时抛错——调用方必须
  /// 保证目标仍在 peers 表(群扇出前过滤已解配成员)。
  int appendOp(String peerId, String type, Uint8List payload) {
    return _tx(() {
      _db.execute(
          'UPDATE peers SET next_op_seq = next_op_seq + 1 WHERE device_id=?',
          [peerId]);
      final rows = _db
          .select('SELECT next_op_seq AS n FROM peers WHERE device_id=?', [peerId]);
      if (rows.isEmpty) {
        throw StateError('appendOp: peer $peerId not in peers table');
      }
      final seq = rows.first['n'] as int;
      _db.execute(
          'INSERT INTO ops (peer_id, pseq, type, payload, created_ms) VALUES (?,?,?,?,?)',
          [peerId, seq, type, payload, DateTime.now().millisecondsSinceEpoch]);
      return seq;
    });
  }

  /// 对端游标之后的全部 op(重连补发)。删除类 op 超过 [deleteOpTtl] 未送达时
  /// 以 **noop 占位**返回:接收方游标按前缀连续推进,直接跳过会把这个
  /// 序号变成永久空洞,ACK 卡死 + 每次重连全量重放。
  static const deleteOpTtlMs = 48 * 3600 * 1000; // 2 天

  List<Op> opsSince(String peerId, int seq) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = _db.select(
        'SELECT * FROM ops WHERE peer_id=? AND pseq>? ORDER BY pseq ASC',
        [peerId, seq]);
    final out = <Op>[];
    for (final r in rows) {
      final type = r['type'] as String;
      final created = (r['created_ms'] as int?) ?? 0;
      if ((type == Op.typeDelete || type == Op.typeClear) &&
          created > 0 &&
          now - created > deleteOpTtlMs) {
        // 过期墓碑:不再补发内容,但保留序号占位推进对端游标。
        out.add(Op(
          seq: r['pseq'] as int,
          peerId: peerId,
          type: Op.typeNoop,
          payload: Uint8List(0),
        ));
        continue;
      }
      out.add(Op(
        seq: r['pseq'] as int,
        peerId: r['peer_id'] as String,
        type: type,
        payload: r['payload'] as Uint8List,
      ));
    }
    return out;
  }

  /// 对端已 ACK 的 op 压缩清理。
  void compactOps(String peerId, int ackedSeq) {
    _db.execute('DELETE FROM ops WHERE peer_id=? AND pseq<=?',
        [peerId, ackedSeq]);
  }

  // ---------------------------------------------------------------- groups

  void insertGroup(Group g) {
    // 三步写在同一事务:崩溃窗口"群存在但成员为空"会让群消息静默不扇出。
    _tx(() {
      _db.execute(
          'INSERT OR REPLACE INTO groups (group_id, name, created_at_ms) VALUES (?,?,?)',
          [g.id, g.name, g.createdAtMs]);
      _db.execute('DELETE FROM group_members WHERE group_id=?', [g.id]);
      for (final m in g.memberIds) {
        _db.execute(
            'INSERT OR IGNORE INTO group_members (group_id, device_id) VALUES (?,?)',
            [g.id, m]);
      }
    });
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
  ///
  /// ⚠ 不再按 peer_id 删除 ops:ops 表按成员 deviceId 入账、不区分 1:1 与群,
  /// 按成员删会把发给该成员的所有未 ACK 1:1 消息一并摧毁(且把刚广播的
  /// 解散 op 自己删掉,离线成员永远收不到解散通知)。群 op 留待对端 ACK
  /// 后自然压缩;接收端收到解散通知时自行清理本地群数据。
  void deleteGroup(String groupId, {bool keepMessages = false}) {
    final convId = Group.convIdOf(groupId);
    _tx(() {
      _db.execute('DELETE FROM groups WHERE group_id=?', [groupId]);
      _db.execute('DELETE FROM group_members WHERE group_id=?', [groupId]);
      if (!keepMessages) {
        _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
        _db.execute('DELETE FROM conversations WHERE conv_id=?', [convId]);
      }
    });
  }

  /// 群成员(不含本机;且必须仍是已配对 peer——解配的成员留在群定义里
  /// 只是历史信息,向其扇出会在 appendOp 处抛错)。
  List<String> groupRecipients(String groupId) {
    final g = getGroup(groupId);
    if (g == null) return const [];
    return g.memberIds
        .where((id) => id != _dbSelfId && getPeer(id) != null)
        .toList();
  }

  /// 从所有群定义里移除某设备(解绑时调用,防止后续扇出命中已删 peer)。
  void removeFromAllGroups(String deviceId) {
    _db.execute('DELETE FROM group_members WHERE device_id=?', [deviceId]);
  }

  /// 引擎启动时注入本机设备 ID(群收件人过滤用)。空 = 未注入(全保留)。
  set selfDeviceId(String id) => _dbSelfId = id;

  String _dbSelfId = '';

  /// 把列表切成 ≤[size] 的批(IN 子句参数上限防护)。
  static Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, math.min(i + size, list.length));
    }
  }

  // -------------------------------------------------------- unpair outbox

  /// 排一条"待送达的解绑通知"(对端离线时入箱,链路恢复时补发)。
  void queueUnpairNotice(Peer peer) {
    _db.execute(
        'INSERT OR REPLACE INTO unpair_outbox (device_id, cert_fingerprint, token, created_ms) VALUES (?,?,?,?)',
        [peer.deviceId, peer.certFingerprint, peer.token,
            DateTime.now().millisecondsSinceEpoch]);
  }

  List<Peer> unpairOutbox() => _db
      .select('SELECT * FROM unpair_outbox ORDER BY created_ms ASC')
      .map((r) => Peer(
            deviceId: r['device_id'] as String,
            deviceName: '',
            platform: '',
            certFingerprint: r['cert_fingerprint'] as String,
            token: r['token'] as String,
            pairedAtMs: r['created_ms'] as int,
          ))
      .toList();

  void clearUnpairNotice(String deviceId) {
    _db.execute('DELETE FROM unpair_outbox WHERE device_id=?', [deviceId]);
  }
}
