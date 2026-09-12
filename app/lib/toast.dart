import 'package:flutter/material.dart';

/// 全局 ScaffoldMessenger 句柄(挂在 MaterialApp 上)。
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastType { success, error, info }

/// 全局 toast:任意位置调用,无需 BuildContext。
/// success=绿色对勾 / error=红色叉(展示更久)/ info=中性。
void showToast(
  String message, {
  ToastType type = ToastType.info,
  Duration? duration,
}) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) return;

  final (icon, bg) = switch (type) {
    ToastType.success => (Icons.check_circle_outline, Colors.green.shade600),
    ToastType.error => (Icons.cancel_outlined, Colors.red.shade400),
    ToastType.info => (Icons.info_outline, const Color(0xFF323232)),
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: duration ??
            Duration(seconds: type == ToastType.error ? 5 : 2),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
}
