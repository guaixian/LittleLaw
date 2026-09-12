/// 分片二维码工具:超长内容切成多个小帧,每帧都是独立可扫的小二维码,
/// 接收方逐帧扫描后按序拼回原内容。
///
/// 帧格式:`LLQ2.<total>.<seq>.<payload>`
///   total: 总帧数;seq: 帧序号(1 起);payload: 内容片段。
class QrChunker {
  QrChunker._();

  static const framePrefix = 'LLQ2.';
  static const defaultChunkSize = 260; // 每帧载荷字符数(小体积,低密度二维码)

  /// 是否为分片帧。
  static bool isChunk(String text) => text.trim().startsWith(framePrefix);

  /// 切分为帧序列(有序)。
  static List<String> split(String payload, {int chunkSize = defaultChunkSize}) {
    if (payload.isEmpty) return [];
    final chunks = <String>[];
    for (var i = 0; i < payload.length; i += chunkSize) {
      final end = i + chunkSize > payload.length ? payload.length : i + chunkSize;
      chunks.add(payload.substring(i, end));
    }
    final total = chunks.length;
    return [
      for (var seq = 0; seq < total; seq++)
        '$framePrefix$total.${seq + 1}.${chunks[seq]}',
    ];
  }

  /// 解析帧头。非分片帧返回 null。
  static ({int total, int seq, String payload})? parseFrame(String text) {
    final t = text.trim();
    if (!t.startsWith(framePrefix)) return null;
    final rest = t.substring(framePrefix.length);
    final dot1 = rest.indexOf('.');
    if (dot1 <= 0) return null;
    final dot2 = rest.indexOf('.', dot1 + 1);
    if (dot2 <= dot1) return null;
    final total = int.tryParse(rest.substring(0, dot1));
    final seq = int.tryParse(rest.substring(dot1 + 1, dot2));
    if (total == null || seq == null || total <= 0 || seq <= 0 || seq > total) {
      return null;
    }
    return (total: total, seq: seq, payload: rest.substring(dot2 + 1));
  }
}

/// 重组器:收集帧直到齐套,输出原内容。顺序无关、可去重。
class QrReassembler {
  int? _total;
  final _parts = <int, String>{};

  int get total => _total ?? 0;
  int get received => _parts.length;
  bool get complete => _total != null && _parts.length == _total;

  /// 喂入一帧。返回是否为新有效帧。齐套后 [payload] 可用。
  bool add(String frameText) {
    final frame = QrChunker.parseFrame(frameText);
    if (frame == null) return false;
    // 不同批次(total 不一致)重置。
    if (_total != frame.total) {
      _total = frame.total;
      _parts.clear();
    }
    if (_parts.containsKey(frame.seq)) return false;
    _parts[frame.seq] = frame.payload;
    return true;
  }

  /// 齐套后拼回原内容,否则 null。
  String? get payload {
    if (!complete) return null;
    final sb = StringBuffer();
    for (var i = 1; i <= _total!; i++) {
      sb.write(_parts[i]);
    }
    return sb.toString();
  }

  void reset() {
    _total = null;
    _parts.clear();
  }
}
