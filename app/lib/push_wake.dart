import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

/// FCM 离线推送唤醒(可选增强):
///  - 有 Firebase 配置(google-services.json)时:注册推送令牌到中转服务器,
///    收到离线信封时服务器代发唤醒(仅信号,无内容);
///  - 未配置 Firebase 时:整体静默禁用,不影响任何功能。
class PushWake {
  PushWake._();

  static Future<void> attach(LittleLawEngine engine) async {
    // 1) 未放 google-services.json / GoogleService-Info.plist 时初始化会抛异常。
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return; // 未配置 Firebase:静默禁用
    }

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
          alert: false, badge: true, sound: false);

      void register(String? token) {
        final rc = engine.rendezvous;
        if (rc == null || !rc.connected || token == null || token.isEmpty) {
          return;
        }
        rc.registerPushToken(token, Platform.isIOS ? 'ios' : 'android');
      }

      // 已连接则立即注册;令牌轮换时重新注册。
      register(await messaging.getToken());
      FirebaseMessaging.instance.onTokenRefresh.listen(register);
      // 服务器重连后补注册。
      engine.rendezvous?.connectionState.listen((up) {
        if (up) {
          messaging.getToken().then(register);
        }
      });

      // 前台收到推送:立即拉取离线邮箱。
      FirebaseMessaging.onMessage.listen((_) {
        engine.rendezvous?.fetchMailbox();
      });
      // 后台/被杀时被唤醒:系统拉起应用,启动流程自然完成注册与同步。
    } catch (_) {
      // 权限被拒或插件异常:禁用
    }
  }
}
