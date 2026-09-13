import 'package:flutter/material.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

import 'call.dart';
import 'webrtc_link.dart';

/// 全局导航键(弹页/事件直接跳转)。
final navigatorKey = GlobalKey<NavigatorState>();

/// 全局引擎引用(BootPage 初始化;气泡等无 context 组件用)。
LittleLawEngine? activeEngine;

/// 全局 WebRTC 链路管理器(BootPage 初始化)。
WebRtcLinkManager? rtcManager;

/// 全局通话管理器(BootPage 初始化)。
CallManager? callManager;
