import 'dart:typed_data';

/// Base45 编解码(RFC 9285)。
///
/// 字符集与 QR 字母数字(Alphanumeric)模式完全一致,配合该模式时
/// 每字符承载 5.5 bit 数据,远优于 base64+字节模式(8 bit/6bit)。
/// 编码规则:2 字节 → 3 字符(低位数字在前,按 RFC 9285 §4);
/// 末尾单字节 → 2 字符。
class Base45 {
  Base45._();

  static const String alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

  static final _reverse = () {
    final map = <int, int>{};
    for (var i = 0; i < alphabet.length; i++) {
      map[alphabet.codeUnitAt(i)] = i;
    }
    return map;
  }();

  /// 字符集是否全部落在 base45 字母表内(QR alphanumeric 模式判定用)。
  static bool isBase45Charset(String s) {
    for (final c in s.codeUnits) {
      if (!_reverse.containsKey(c)) return false;
    }
    return true;
  }

  static String encode(List<int> bytes) {
    final sb = StringBuffer();
    var i = 0;
    while (i + 1 < bytes.length) {
      final n = (bytes[i] << 8) | bytes[i + 1];
      // RFC 9285:n = c0 + c1*45 + c2*45^2,依次输出 c0 c1 c2(低位在前)。
      sb.write(alphabet[n % 45]);
      sb.write(alphabet[(n ~/ 45) % 45]);
      sb.write(alphabet[(n ~/ 45 ~/ 45) % 45]);
      i += 2;
    }
    if (i < bytes.length) {
      final n = bytes[i];
      sb.write(alphabet[n % 45]);
      sb.write(alphabet[n ~/ 45]);
    }
    return sb.toString();
  }

  static Uint8List decode(String text) {
    final units = text.codeUnits;
    final out = BytesBuilder();
    var i = 0;
    while (i + 2 < units.length) {
      final c0 = _value(units[i]);
      final c1 = _value(units[i + 1]);
      final c2 = _value(units[i + 2]);
      final x = c0 + c1 * 45 + c2 * 45 * 45;
      if (x > 65535) {
        throw const FormatException('base45 数据损坏(值越界)');
      }
      out.addByte((x >> 8) & 0xFF);
      out.addByte(x & 0xFF);
      i += 3;
    }
    if (i < units.length) {
      // 末尾 2 字符 → 1 字节。
      if (i + 1 >= units.length) {
        throw const FormatException('base45 长度非法');
      }
      final c0 = _value(units[i]);
      final c1 = _value(units[i + 1]);
      final x = c0 + c1 * 45;
      if (x > 255) {
        throw const FormatException('base45 数据损坏(值越界)');
      }
      out.addByte(x);
    }
    return out.toBytes();
  }

  static int _value(int unit) {
    final v = _reverse[unit];
    if (v == null) {
      throw FormatException(
          'base45 非法字符: ${String.fromCharCode(unit)}');
    }
    return v;
  }
}
