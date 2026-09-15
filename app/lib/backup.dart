import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'toast.dart';

/// 备份与恢复:打包身份 + 消息库 + 收件箱元数据,口令加密。
///
/// 安全约束:
///  - 解包白名单:只接受固定 4 个文件名,拒绝一切路径穿越(Zip Slip);
///  - 解包/落盘全部在本端数据目录 tmp 下,不进系统共享临时目录;
///  - 恢复先全部解包校验,再 dispose 引擎,最后逐文件 rename 到位(近原子)。
class BackupManager {
  BackupManager(this._engine);
  final LittleLawEngine _engine;

  static const _backupFiles = [
    'littlelaw.db',
    'identity.crt',
    'identity.key',
    'identity.json',
  ];

  /// 数据目录下的临时工作区(唯一临时位置约定,启动时可整体清理)。
  static Directory _tmpArea(String dataDir) {
    final d = Directory('$dataDir/tmp');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 启动时清理:上次异常退出残留的 restore_* 工作区。
  static void cleanupResidual(String dataDir) {
    try {
      final d = Directory('$dataDir/tmp');
      if (!d.existsSync()) return;
      for (final e in d.listSync()) {
        final name = e.path.replaceAll('\\', '/').split('/').last;
        if (name.startsWith('restore_')) {
          try {
            e.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

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
    // file_picker 12.x 返回 Uri;平台已用传入的 bytes 自动写盘。
    String savePath;
    if (result.isScheme('file')) {
      savePath = result.toFilePath();
      // 个别平台不落盘的兜底:确认不存在才手动写。
      if (!File(savePath).existsSync()) {
        await File(savePath).writeAsBytes(blob);
      }
    } else {
      // content:// (Android SAF)等:平台已写入,仅展示 URI。
      savePath = result.toString();
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

    // 白名单解包:只认固定文件名,拒绝一切目录分量/路径穿越(Zip Slip)。
    final rand = Random.secure();
    final tag = List<int>.generate(6, (_) => rand.nextInt(16))
        .map((b) => b.toRadixString(16))
        .join();
    final tmp = Directory('${_tmpArea(_engine.dataDir).path}/restore_$tag');
    try {
      tmp.createSync(recursive: true);
      final extracted = <String>[];
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name;
        if (!_backupFiles.contains(name)) {
          // 未知条目:可能是恶意构造,直接拒绝恢复。
          throw '备份中包含不认识的条目 "$name",已取消恢复';
        }
        final out = File('${tmp.path}/$name');
        await out.writeAsBytes(file.content as List<int>);
        extracted.add(name);
      }

      // 引擎此时仍在运行(读旧库);全部解包成功后才停引擎、换文件。
      await _engine.dispose();
      final dir = Directory(_engine.dataDir);
      try {
        for (final name in _backupFiles) {
          final src = File('${tmp.path}/$name');
          final dst = File('${dir.path}/$name');
          if (await src.exists()) {
            // rename 同盘近原子;失败(占用)退化为 copy+delete。
            try {
              if (await dst.exists()) await dst.delete();
              await src.rename(dst.path);
            } catch (_) {
              await src.copy(dst.path);
              await src.delete();
            }
          }
        }
      } catch (e) {
        showToast('恢复中断: $e。请立即重启应用', type: ToastType.error);
        return true; // 引擎已 disposed,必须重启
      }
      return true;
    } catch (e) {
      showToast('$e', type: ToastType.error);
      return false;
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
