import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

void main() {
  test('备份编解码:加密往返 / 口令错误拒绝 / 格式校验', () async {
    final data =
        Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
    final blob = await BackupCodec.encrypt(data, '正确口令123');
    expect(blob.length, greaterThan(data.length));

    final plain = await BackupCodec.decrypt(blob, '正确口令123');
    expect(plain, equals(data));

    // 错口令。
    await expectLater(
        BackupCodec.decrypt(blob, '错误口令456'), throwsStateError);

    // 非 LLBK 格式。
    await expectLater(
        BackupCodec.decrypt(List<int>.filled(200, 7), '正确口令123'),
        throwsStateError);
  });
}
