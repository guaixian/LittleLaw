import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'toast.dart';

/// 备份与恢复:打包身份 + 消息库 + 收件箱元数据,口令加密。
class BackupManager {
  BackupManager(this._engine);
  final LittleLawEngine _engine;

  static const _backupFiles = [
    'littlelaw.db',
    'identity.crt',
    'identity.key',
    'identity.json',
  ];

  /// 创建加密备份,返回保存路径(用户取消返回 null)。
  Future<String?> createBackup(String passphrase) async {
    if (passphrase.length < 6) {
      showToast('口令至少 6 个字符', type: ToastType.error);
      return null;
    }
    _engine.checkpointDb();
    final archive = Archive();
    final dir = Directory(_engine.dataDir);
    for (final name in _backupFiles) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) {
        final data = await f.readAsBytes();
        archive.add(ArchiveFile(name, data.length, data));
      }
    }
    if (!archive.files.any((f) => f.name == 'littlelaw.db')) {
      showToast('数据文件缺失,无法备份', type: ToastType.error);
      return null;
    }
    final zip = ZipEncoder().encode(archive);
    final blob = await BackupCodec.encrypt(zip, passphrase);

    final ts = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final defaultName =
        'littlelaw-backup-${ts.year}${two(ts.month)}${two(ts.day)}-${two(ts.hour)}${two(ts.minute)}.llbk';
    final result = await FilePicker.saveFile(
      fileName: defaultName,
      bytes: blob,
    );
    if (result == null) return null;
    final savePath = result.toString();
    if (!File(savePath).existsSync()) {
      // 平台未自动写盘时手动落盘。
      await File(savePath).writeAsBytes(blob);
    }
    showToast('备份已保存', type: ToastType.success);
    return savePath;
  }

  /// 恢复备份:解密解包校验后写入数据目录。
  /// 返回 true 表示需要重启应用生效。
  Future<bool> restoreBackup(String path, String passphrase) async {
    final bytes = await File(path).readAsBytes();
    final zip = await BackupCodec.decrypt(bytes, passphrase);
    final archive = ZipDecoder().decodeBytes(zip);
    final names = archive.files.map((f) => f.name).toSet();
    if (!names.contains('littlelaw.db') || !names.contains('identity.json')) {
      showToast('备份内容不完整', type: ToastType.error);
      return false;
    }
    // 先解到临时目录,全部成功后再覆盖,避免半恢复状态。
    final tmp = Directory.systemTemp.createTempSync('ll_restore_');
    try {
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final out = File('${tmp.path}/${file.name}');
        await out.writeAsBytes(file.content as List<int>);
      }
      await _engine.dispose();
      final dir = Directory(_engine.dataDir);
      for (final name in _backupFiles) {
        final src = File('${tmp.path}/$name');
        if (await src.exists()) {
          await src.copy('${dir.path}/$name');
        }
      }
      return true;
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
