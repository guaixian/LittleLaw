import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// 分片二维码工具:超长内容切成多个小帧,每帧都是独立可扫的小二维码,
/// 接收方逐帧扫描后按序拼回原内容。
///
/// 帧格式(v3):`LLQ3.<batch>.<total>.<seq>.<payload>`
///   batch: 6 位十六进制随机批次 ID——多份引导包二维码并排/先后展示时,
///          相同 total 的帧交错也不会被拼成两份载荷的杂糅体;
///   total: 总帧数;seq: 帧序号(1 起);
///   第 1 帧额外携带全载荷 SHA-256:`LLQ3.<batch>.<total>.1.<sha256>.<payload>`,
///   齐套后终检,拼错的流直接判定失败而不是静默产出错误引导包
///   (配对指纹/token 错配的后果不可接受)。
///
/// 旧格式 LLQ2(无批次、无校验)仍可解析,仅用于兼容历史帧。
class QrChunker {
  QrChunker._();

  static const framePrefix = 'LLQ3.';
  static const legacyPrefix = 'LLQ2.';
  // 每帧载荷字符数(小体积,低密度二维码)。v3 帧头含批次 ID,
  // 第 1 帧还带 64-hex 摘要,总长按 ~290 字符封顶保持 QR 低密度。
  static const defaultChunkSize = 200;

  /// 是否为分片帧(LLQ2 / LLQ3)。
  /// 注意:只剥离换行类空白——base45 字母表含空格,trim() 会截掉
  /// 结尾为空格的合法载荷,与 parseFrame 口径一致。
  static bool isChunk(String text) {
    final t = text.replaceAll(RegExp(r'[\r\n\t]'), '');
    return t.startsWith(framePrefix) || t.startsWith(legacyPrefix);
  }

  /// 切分为帧序列(有序)。
  static List<String> split(String payload, {int chunkSize = defaultChunkSize}) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
    if (payload.isEmpty) return [];
    final digest = sha256.convert(payload.codeUnits).toString();
    final chunks = <String>[];
    for (var i = 0; i < payload.length; i += chunkSize) {
      final end = i + chunkSize > payload.length ? payload.length : i + chunkSize;
      chunks.add(payload.substring(i, end));
    }
    final total = chunks.length;
    final batch = _randomBatch();
    return [
      for (var seq = 0; seq < total; seq++)
        seq == 0
            ? '$framePrefix$batch.$total.1.$digest.${chunks[seq]}'
            : '$framePrefix$batch.$total.${seq + 1}.${chunks[seq]}',
    ];
  }

  static String _randomBatch() {
    final rng = math.Random.secure();
    return List<int>.generate(6, (_) => rng.nextInt(16))
        .map((b) => b.toRadixString(16))
        .join();
  }

  /// 解析帧头。非分片帧返回 null。
  static ({int total, int seq, String payload, String? batch, String? digest})?
      parseFrame(String text) {
    // base45 载荷可能含空格,只剥换行类空白。
    final t = text.replaceAll(RegExp(r'[\r\n\t]'), '');
    if (t.startsWith(framePrefix)) {
      final rest = t.substring(framePrefix.length);
      final d1 = rest.indexOf('.');
      if (d1 <= 0) return null;
      final d2 = rest.indexOf('.', d1 + 1);
      if (d2 <= d1) return null;
      final d3 = rest.indexOf('.', d2 + 1);
      if (d3 <= d2) return null;
      final batch = rest.substring(0, d1);
      final total = int.tryParse(rest.substring(d1 + 1, d2));
      final seq = int.tryParse(rest.substring(d2 + 1, d3));
      if (batch.isEmpty || total == null || seq == null) return null;
      if (total <= 0 || seq <= 0 || seq > total) return null;
      var payload = rest.substring(d3 + 1);
      // 第 1 帧可能携带 64-hex 摘要字段。
      String? digest;
      if (seq == 1) {
        final m = RegExp(r'^([0-9a-f]{64})\.(.*)$').firstMatch(payload);
        if (m != null) {
          digest = m.group(1)!;
          payload = m.group(2)!;
        }
      }
      return (
        total: total,
        seq: seq,
        payload: payload,
        batch: batch,
        digest: digest
      );
    }
    if (t.startsWith(legacyPrefix)) {
      final rest = t.substring(legacyPrefix.length);
      final dot1 = rest.indexOf('.');
      if (dot1 <= 0) return null;
      final dot2 = rest.indexOf('.', dot1 + 1);
      if (dot2 <= dot1) return null;
      final total = int.tryParse(rest.substring(0, dot1));
      final seq = int.tryParse(rest.substring(dot1 + 1, dot2));
      if (total == null || seq == null || total <= 0 || seq <= 0 || seq > total) {
        return null;
      }
      return (
        total: total,
        seq: seq,
        payload: rest.substring(dot2 + 1),
        batch: null,
        digest: null
      );
    }
    return null;
  }
}

/// 重组器:收集帧直到齐套,输出原内容。顺序无关、可去重。
/// 按 batch 分流:不同批次的帧互不污染;同 seq 不同内容视为新流重置。
/// 齐套后做 SHA-256 终检(LLQ3),不匹配返回 null 并自动重置。
class QrReassembler {
  String? _batch;
  int? _total;
  String? _digest;
  final _parts = <int, String>{};

  int get total => _total ?? 0;
  int get received => _parts.length;
  bool get complete => _total != null && _parts.length == _total;

  /// 喂入一帧。返回是否为新有效帧。齐套后 [payload] 可用。
  bool add(String frameText) {
    final frame = QrChunker.parseFrame(frameText);
    if (frame == null) return false;
    // 不同批次(batch 或 total 变化)重置为新流。
    if (_batch != frame.batch || _total != frame.total) {
      _batch = frame.batch;
      _total = frame.total;
      _digest = frame.digest;
      _parts.clear();
    }
    _digest ??= frame.digest;
    final existing = _parts[frame.seq];
    if (existing != null) {
      if (existing == frame.payload) return false; // 重复帧,忽略
      // 同 seq 不同内容:说明开始了另一份同规格的流 → 重置收这份。
      _parts.clear();
      _digest = frame.digest;
    }
    _parts[frame.seq] = frame.payload;
    return true;
  }

  /// 齐套后拼回原内容并终检;不完整或校验失败返回 null。
  String? get payload {
    if (!complete) return null;
    final sb = StringBuffer();
    for (var i = 1; i <= _total!; i++) {
      sb.write(_parts[i]);
    }
    final joined = sb.toString();
    if (_digest != null &&
        sha256.convert(joined.codeUnits).toString() != _digest) {
      // 杂糅/损坏流:不产出错误载荷(静默配到错误设备比失败更糟)。
      reset();
      return null;
    }
    return joined;
  }

  void reset() {
    _batch = null;
    _total = null;
    _digest = null;
    _parts.clear();
  }
}
