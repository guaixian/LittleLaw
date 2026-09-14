import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 智能二维码:自动选择最优编码模式渲染。
///
/// 内容落在 base45 字符集(QR 字母数字集)时走 Alphanumeric 模式
/// (每字符 5.5bit,面积比字节模式小 ~31%);否则回退字节模式。
/// 自动挑选能容纳数据的最小版本(码点更粗,更好扫)。
class SmartQrView extends StatelessWidget {
  const SmartQrView({super.key, required this.data, this.size = 260});

  final String data;
  final double size;

  /// 构造 QrCode:选最优模式 + 最小可用版本。塞不下返回 null。
  QrCode? _build() {
    final useAlpha = Base45.isBase45Charset(data);
    for (var v = 1; v <= 40; v++) {
      final code = QrCode(v, QrErrorCorrectLevel.L);
      try {
        if (useAlpha) {
          code.addAlphaNumeric(data);
        } else {
          code.addData(data);
        }
        // 触发编码,超限抛 InputTooLongException。
        // ignore: invalid_use_of_internal_member
        final _ = code.dataCache;
        return code;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final code = _build();
    if (code == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('内容超出单张二维码容量',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12), // 静区
      child: CustomPaint(
        size: Size.square(size),
        painter: QrPainter.withQr(
          qr: code,
          gapless: true,
          eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF000000)),
        ),
      ),
    );
  }
}
