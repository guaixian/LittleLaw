import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:nfc_manager/nfc_manager.dart';

/// NFC 一碰配对:
///  - 本机作为"卡片"(仅 Android HCE):把局域网配对载荷模拟成 NDEF 标签;
///  - 本机作为"读卡器"(Android/iOS):Core NFC / NFC 读对方的 HCE 标签。
/// 读到载荷后直连对方 gRPC,用一次性 tap 令牌完成免 PIN 配对。
class NfcPairManager {
  static const _channel = MethodChannel('dev.littlelaw/hotspot'); // 复用通道

  /// 本机 NFC 是否可用。
  static Future<bool> isAvailable() async {
    try {
      final result = await NfcManager.instance.isAvailable();
      return result;
    } catch (_) {
      return false;
    }
  }

  /// 开启"一碰配对"窗口(本机当被碰方):
  /// 生成配对载荷并写入 HCE 服务,2 分钟内对方触碰即可配对。
  /// 返回载荷文本(同内容也可用于二维码展示)。
  static Future<String> enableTapToPair(LittleLawEngine engine) async {
    final payload = await engine.enableTapPairing();
    if (Platform.isAndroid) {
      await _channel.invokeMethod('setNfcPayload', {'payload': payload});
      // 窗口到期自动清除 HCE 载荷。
      Timer(const Duration(minutes: 2), () {
        _channel.invokeMethod('clearNfcPayload');
      });
    }
    return payload;
  }

  static Future<void> disableTapToPair() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('clearNfcPayload');
    }
  }

  /// 本机当读卡器:启动一次 NFC 读取会话,读到载荷后自动完成配对。
  /// 读到任意 NFC 标签都会回调;非 LittleLaw 载荷则忽略并继续监听。
  static Future<PairResult> readAndPair(LittleLawEngine engine) async {
    final completer = Completer<PairResult>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) return;
          final message = await ndef.read();
          if (message.records.isEmpty) return;
          final record = message.records.first;
          // NDEF 文本记录:payload[0] = 状态字节(低位为语言码长度)。
          final payload = record.payload;
          if (payload.length < 3) return;
          final langLen = payload[0] & 0x3F;
          final text = String.fromCharCodes(payload.sublist(1 + langLen));
          if (!text.startsWith('LLT1.')) return;

          final result = await engine.pairViaLanOob(text);
          if (!completer.isCompleted) completer.complete(result);
          await NfcManager.instance.stopSession();
        } catch (e) {
          if (!completer.isCompleted) {
            completer.complete(PairResult.rejected(e.toString()));
          }
          await NfcManager.instance.stopSession();
        }
      },
    );

    // 60 秒未读到自动超时。
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        NfcManager.instance.stopSession();
        return PairResult.rejected('未读取到设备,请保持贴近后重试');
      },
    );
  }
}
