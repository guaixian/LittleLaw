import 'package:flutter/material.dart';

import 'webrtc_link.dart';

/// 全局导航句柄(任意页面/事件可直接跳转)。
final navigatorKey = GlobalKey<NavigatorState>();

/// 全局 WebRTC 链路管理器(BootPage 初始化)。
WebRtcLinkManager? rtcManager;
