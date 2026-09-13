import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:uuid/uuid.dart';

import '../generated/littlelaw.pb.dart' as pb;
import '../generated/littlelaw.pbgrpc.dart' as pbg;
import '../identity/identity.dart';
import '../store/store.dart';
import '../sync/sync_engine.dart';
import '../transport/auth.dart';
import '../transport/transport.dart';
import '../util.dart';

/// 传输进度事件(UI 进度条)。
class TransferProgress {
  TransferProgress({
    required this.fileId,
    required this.msgId,
    required this.peerId,
    required this.fileName,
    required this.totalBytes,
    required this.doneBytes,
    required this.direction,
    required this.state,
    this.error,
  });

  static const stateRunning = 'running';
  static const stateDone = 'done';
  static const stateFailed = 'failed';
  static const stateCancelled = 'cancelled';

  static const directionSend = 'send';
  static const directionReceive = 'receive';

  final String fileId;
  final String msgId;
  final String peerId;
  final String fileName;
  final int totalBytes;
  final int doneBytes;
  final String direction;
  final String state;
  final String? error;
}

/// 文件传输管理:拉取式数据面。
///
/// 模型:发送方提交文件消息(元数据)后,文件本体由【接收方主动拉取】——
/// 接收方调对端 TransferService.FetchFile(file_id, offset),offset 取
/// 本地 .part 文件大小,天然断点续传。整包 SHA-256 校验后落盘重命名。
class TransferManager extends pbg.TransferServiceBase {
  TransferManager({
    required this.identity,
    required this.store,
    required this.sync,
    required this.inboxDir,
    this.chunkSize = 1 << 20, // 1 MiB
    this.autoAcceptFiles = true,
  });

  final Identity identity;
  final Store store;
  final SyncEngine sync;
  final String inboxDir;

  /// 单帧大小(gRPC 数据面)。
  final int chunkSize;

  /// 信封式数据面单帧(WebRTC DataChannel 安全尺寸)。
  static const envelopeChunkSize = 64 * 1024;

  /// 收到文件消息是否自动开始拉取(false 则由 UI 调 [receiveFile])。
  bool autoAcceptFiles;

  final _progress = StreamController<TransferProgress>.broadcast();
  Stream<TransferProgress> get progress => _progress.stream;

  /// fileId → 发送源路径(本端作为发送方时供 FetchFile 读取)。
  final _sendSources = <String, String>{};

  /// fileId → 拉取任务取消标记。
  final _cancelled = <String>{};

  /// fileId → 正在进行的拉取任务(去重)。
  final _receiving = <String, Future<void>>{};

  /// fileId → 信封式数据帧暂存(接收侧)。
  final _envelopeData = <String, StreamController<pb.FileData>>{};

  /// 窗口背压:发送侧等待 ACK 状态。
  static const _ackWindowFrames = 8;
  final _lastAck = <String, int>{};
  final _ackNotifiers = <String, Completer<void>>{};

  StreamSubscription<EngineEvent>? _eventSub;

  void start() {
    Directory(inboxDir).createSync(recursive: true);
    _eventSub = sync.events.listen((e) {
      if (e is FileMessageArrived && autoAcceptFiles) {
        unawaited(receiveFile(e.peerId, e.message));
      } else if (e is FileCancelled) {
        _cancelled.add(e.fileId);
      } else if (e is FileFetchRequested) {
        unawaited(_serveEnvelopeFetch(e));
      } else if (e is FileDataReceived) {
        _envelopeData[e.data.fileId]?.add(e.data);
      } else if (e is FileDataAcked) {
        // 窗口背压:更新对端已落盘偏移,唤醒发送节奏等待。
        final cur = _lastAck[e.fileId] ?? 0;
        if (e.ackedOffset > cur) _lastAck[e.fileId] = e.ackedOffset;
        _ackNotifiers.remove(e.fileId)?.complete();
      }
    });
  }

  // ------------------------------------------------------------ 发送侧

  /// 发送文件:提交文件消息(同步到对端),之后等对端来拉取。
  /// [kind] 缺省按扩展名识别:图片/视频/普通文件。
  Future<Message> sendFileTo(String peerId, String filePath, {int? kind}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('file not found: $filePath');
    }
    final size = await file.length();
    final fileId = const Uuid().v4();
    final hash = await _sha256OfFile(file);
    _sendSources[fileId] = filePath;

    final convId = Store.convIdFor(identity.deviceId, peerId);
    final msgId = const Uuid().v4();
    final msgKind = kind ?? _kindForPath(filePath);
    final chatMsg = pb.ChatMessage(
      msgId: msgId,
      lamport: Int64(store.nextLamport(convId)),
      createdAtMs: Int64(DateTime.now().millisecondsSinceEpoch),
      kind: msgKind,
      fileId: fileId,
      fileName: file.uri.pathSegments.last,
      fileSize: Int64(size),
      fileSha256: hash,
    );
    final msg = await sync.commitFileMessage(peerId, chatMsg);
    // 本端消息直接标记完成(源文件在本机)。
    store.updateFileState(msgId, Message.fileStateDone, filePath: filePath);
    _emit(TransferProgress(
      fileId: fileId,
      msgId: msgId,
      peerId: peerId,
      fileName: chatMsg.fileName,
      totalBytes: size,
      doneBytes: size,
      direction: TransferProgress.directionSend,
      state: TransferProgress.stateDone,
    ));
    return msg;
  }

  // ------------------------------------------------------------ 接收侧

  /// 拉取对端文件(可重复调用,断点续传)。
  Future<void> receiveFile(String peerId, Message msg) async {
    final fileId = msg.fileId;
    if (fileId == null) return;
    final existing = _receiving[fileId];
    if (existing != null) return existing;

    final task = _doReceive(peerId, msg).whenComplete(() {
      _receiving.remove(fileId);
    });
    _receiving[fileId] = task;
    return task;
  }

  Future<void> _doReceive(String peerId, Message msg) async {
    final fileId = msg.fileId!;
    final peer = store.getPeer(peerId);
    if (peer == null) return;
    final host = peer.lastHost;
    final port = peer.lastPort;
    // 无 gRPC 可达地址(如 WebRTC 跨网链路)→ 走信封式拉取。
    if (host == null || host.isEmpty || port == null) {
      return _doReceiveViaEnvelope(peerId, msg);
    }

    final partPath = '$inboxDir/$fileId.part';
    final finalPath = await _dedupePath('$inboxDir/${msg.fileName ?? fileId}');
    final partFile = File(partPath);
    var offset = await partFile.exists() ? await partFile.length() : 0;

    store.updateFileState(msg.msgId, Message.fileStateTransferring);

    final ch = PeerChannel.connect(
      host: host,
      port: port,
      pinnedFingerprint: peer.certFingerprint,
    );
    IOSink? sink;
    try {
      final client = pbg.TransferServiceClient(ch.channel);
      final stream = client.fetchFile(
        pb.FetchRequest(fileId: fileId, offset: Int64(offset)),
        options: CallOptions(
          metadata: Auth.metadata(identity.deviceId, peer.token),
          timeout: const Duration(minutes: 30),
        ),
      );

      sink = partFile.openWrite(mode: FileMode.append);
      var received = offset;
      await for (final chunk in stream) {
        if (_cancelled.contains(fileId)) {
          throw _TransferCancelled();
        }
        if (chunk.hasData()) {
          sink.add(chunk.data);
          received += chunk.data.length;
          _emit(TransferProgress(
            fileId: fileId,
            msgId: msg.msgId,
            peerId: peerId,
            fileName: msg.fileName ?? fileId,
            totalBytes: msg.fileSize ?? 0,
            doneBytes: received,
            direction: TransferProgress.directionReceive,
            state: TransferProgress.stateRunning,
          ));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // 整包校验(发送方在消息里宣告的 SHA-256)。
      final digest = await _sha256OfFile(partFile);
      final expected = msg.fileSha256;
      final ok = expected == null || expected.isEmpty || digest == expected;
      if (!ok) {
        await partFile.delete(); // 校验失败不留坏文件
        _fail(msg, peerId, 'sha256 mismatch');
        return;
      }
      await partFile.rename(finalPath);
      store.updateFileState(msg.msgId, Message.fileStateDone,
          filePath: finalPath);
      _emit(TransferProgress(
        fileId: fileId,
        msgId: msg.msgId,
        peerId: peerId,
        fileName: msg.fileName ?? fileId,
        totalBytes: msg.fileSize ?? received,
        doneBytes: received,
        direction: TransferProgress.directionReceive,
        state: TransferProgress.stateDone,
      ));
    } on _TransferCancelled {
      await sink?.close();
      store.updateFileState(msg.msgId, Message.fileStatePending);
      _emit(TransferProgress(
        fileId: fileId,
        msgId: msg.msgId,
        peerId: peerId,
        fileName: msg.fileName ?? fileId,
        totalBytes: msg.fileSize ?? 0,
        doneBytes: offset,
        direction: TransferProgress.directionReceive,
        state: TransferProgress.stateCancelled,
      ));
    } catch (e) {
      await sink?.close();
      _fail(msg, peerId, e.toString());
    } finally {
      _cancelled.remove(fileId);
      await ch.shutdown();
    }
  }

  // ---------------------------------------------------- 信封式数据面

  /// 经任意已建立的信封链路(WebRTC 等)拉取文件。断点续传同 gRPC 路径。
  Future<void> _doReceiveViaEnvelope(String peerId, Message msg) async {
    final fileId = msg.fileId!;
    final partPath = '$inboxDir/$fileId.part';
    final finalPath = await _dedupePath('$inboxDir/${msg.fileName ?? fileId}');
    final partFile = File(partPath);
    final offset = await partFile.exists() ? await partFile.length() : 0;

    store.updateFileState(msg.msgId, Message.fileStateTransferring);
    final dataStream = StreamController<pb.FileData>();
    _envelopeData[fileId] = dataStream;

    IOSink? sink;
    try {
      sink = partFile.openWrite(mode: FileMode.append);
      // 发送拉取请求。
      sync.sendEnvelope(peerId, pb.Envelope(
        id: const Uuid().v4(),
        fileFetch: pb.FileFetchRequest(fileId: fileId, offset: Int64(offset)),
      ));

      var received = offset;
      var gotLast = false;
      // 30 秒无数据视为停滞失败(.part 保留,可重试续传)。
      await for (final frame in dataStream.stream.timeout(
          const Duration(seconds: 30))) {
        if (_cancelled.contains(fileId)) throw _TransferCancelled();
        if (frame.offset.toInt() != received) {
          throw StateError('帧偏移错乱: 期望 $received, 收到 ${frame.offset}');
        }
        sink.add(frame.data);
        received += frame.data.length;
        if (frame.last) gotLast = true;
        // 数据帧回执(窗口背压):回报已落盘偏移。
        sync.sendEnvelope(peerId, pb.Envelope(
          id: const Uuid().v4(),
          fileDataAck: pb.FileDataAck(
              fileId: fileId, ackedOffset: Int64(received)),
        ));
        _emit(TransferProgress(
          fileId: fileId,
          msgId: msg.msgId,
          peerId: peerId,
          fileName: msg.fileName ?? fileId,
          totalBytes: msg.fileSize ?? 0,
          doneBytes: received,
          direction: TransferProgress.directionReceive,
          state: TransferProgress.stateRunning,
        ));
        if (frame.last) break;
      }
      if (!gotLast) throw StateError('传输中断,未收到结束帧');
      await sink.flush();
      await sink.close();
      sink = null;

      final digest = await _sha256OfFile(partFile);
      final expected = msg.fileSha256;
      if (expected != null && expected.isNotEmpty && digest != expected) {
        await partFile.delete();
        _fail(msg, peerId, 'sha256 mismatch');
        return;
      }
      await partFile.rename(finalPath);
      store.updateFileState(msg.msgId, Message.fileStateDone,
          filePath: finalPath);
      _emit(TransferProgress(
        fileId: fileId,
        msgId: msg.msgId,
        peerId: peerId,
        fileName: msg.fileName ?? fileId,
        totalBytes: msg.fileSize ?? received,
        doneBytes: received,
        direction: TransferProgress.directionReceive,
        state: TransferProgress.stateDone,
      ));
    } on _TransferCancelled {
      await sink?.close();
      store.updateFileState(msg.msgId, Message.fileStatePending);
    } catch (e) {
      await sink?.close();
      _fail(msg, peerId, e.toString());
    } finally {
      _envelopeData.remove(fileId);
      unawaited(dataStream.close());
      _cancelled.remove(fileId);
    }
  }

  /// 响应对端的信封式拉取请求(发送侧):按窗口(8 帧)节奏分帧发送,
  /// 带背压——慢链路不会撑爆缓冲;ACK 超时即中止(接收方可断点重试)。
  Future<void> _serveEnvelopeFetch(FileFetchRequested req) async {
    final path = _sendSources[req.fileId] ?? _findSentFile(req.fileId);
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;

    var offset = req.offset;
    final total = await file.length();
    _lastAck[req.fileId] = offset;
    final raf = await file.open();
    try {
      while (offset < total) {
        // 背压:在途未确认字节达到窗口上限时等待 ACK。
        while (offset - (_lastAck[req.fileId] ?? offset) >=
            _ackWindowFrames * envelopeChunkSize) {
          final notifier = Completer<void>();
          _ackNotifiers[req.fileId] = notifier;
          var timedOut = false;
          await notifier.future.timeout(const Duration(seconds: 30),
              onTimeout: () => timedOut = true);
          if (timedOut) return; // 对端停滞:中止(.part 保留,可续传)
        }
        if (_cancelled.contains(req.fileId)) return;
        final end = (offset + envelopeChunkSize > total)
            ? total
            : offset + envelopeChunkSize;
        final chunk = await raf.read(end - offset);
        sync.sendEnvelope(req.peerId, pb.Envelope(
          id: const Uuid().v4(),
          fileData: pb.FileData(
            fileId: req.fileId,
            offset: Int64(offset),
            data: chunk,
            last: end >= total,
          ),
        ));
        offset = end;
      }
      // 零字节文件:补发空 last 帧收尾。
      if (offset == req.offset) {
        sync.sendEnvelope(req.peerId, pb.Envelope(
          id: const Uuid().v4(),
          fileData: pb.FileData(
              fileId: req.fileId,
              offset: Int64(offset),
              data: const [],
              last: true),
        ));
      }
    } finally {
      await raf.close();
      _lastAck.remove(req.fileId);
      _ackNotifiers.remove(req.fileId);
    }
  }

  void cancelReceive(String fileId) {
    _cancelled.add(fileId);
  }

  /// 按扩展名识别消息类型。
  static int _kindForPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return Message.kindFile;
    final ext = path.substring(dot + 1).toLowerCase();
    const images = {
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif'
    };
    const videos = {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'flv', 'wmv', 'ts'};
    if (images.contains(ext)) return Message.kindImage;
    if (videos.contains(ext)) return Message.kindVideo;
    return Message.kindFile;
  }

  void _fail(Message msg, String peerId, String error) {
    store.updateFileState(msg.msgId, Message.fileStateFailed);
    _emit(TransferProgress(
      fileId: msg.fileId ?? '',
      msgId: msg.msgId,
      peerId: peerId,
      fileName: msg.fileName ?? '',
      totalBytes: msg.fileSize ?? 0,
      doneBytes: 0,
      direction: TransferProgress.directionReceive,
      state: TransferProgress.stateFailed,
      error: error,
    ));
  }

  // ------------------------------------------------------------ 服务端

  @override
  Stream<pb.FileChunk> fetchFile(
      ServiceCall call, pb.FetchRequest request) async* {
    Auth.verify(call, store); // 仅可信设备可拉取
    final fileId = request.fileId;
    final path = _sendSources[fileId] ?? _findSentFile(fileId);
    if (path == null) {
      throw GrpcError.notFound('unknown file_id');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw GrpcError.failedPrecondition('file no longer exists');
    }

    final offset = request.offset.toInt();
    final reader = file.openRead(offset);
    await for (final data in reader) {
      var index = 0;
      while (index < data.length) {
        final end =
            (index + chunkSize > data.length) ? data.length : index + chunkSize;
        yield pb.FileChunk(data: data.sublist(index, end));
        index = end;
      }
    }
  }

  /// 重启后 _sendSources 丢失:从消息表反查本端或"我的设备"发出的文件路径。
  String? _findSentFile(String fileId) {
    // 自己发的。
    final mine = store.findMessageByFileId(fileId,
        senderId: identity.deviceId);
    if (mine?.filePath != null) return mine!.filePath;
    // 我的设备镜像来的(文件本体在对端,可按普通配对通道拉取)。
    for (final self in store.selfPeers()) {
      final m = store.findMessageByFileId(fileId, senderId: self.deviceId);
      if (m?.filePath != null) return m!.filePath;
    }
    return null;
  }

  @override
  Future<pb.FileResult> sendFile(
      ServiceCall call, Stream<pb.FileChunk> request) async {
    // 推送式传输保留:当前架构统一走拉取式,此方法返回未实现。
    throw GrpcError.unimplemented('push transfer not used; pull via FetchFile');
  }

  // ------------------------------------------------------------ 工具

  Future<String> _sha256OfFile(File file) async {
    final acc = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(acc);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    acc.close();
    return acc.events.single.toString();
  }

  /// 同名文件自动加 (1)(2) 后缀。
  Future<String> _dedupePath(String path) async {
    if (!await File(path).exists()) return path;
    final dot = path.lastIndexOf('.');
    final stem = dot > 0 ? path.substring(0, dot) : path;
    final ext = dot > 0 ? path.substring(dot) : '';
    for (var i = 1;; i++) {
      final candidate = '$stem ($i)$ext';
      if (!await File(candidate).exists()) return candidate;
    }
  }

  void _emit(TransferProgress p) => _progress.add(p);

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _progress.close();
  }
}

class _TransferCancelled implements Exception {}
