# 12 · 在线状态 —— 对方下线后状态反复闪跳（"弹几次在线"才稳定离线）

- **优先级**: P1
- **涉及文件**: `core/lib/src/sync/sync_engine.dart`、`core/lib/src/discovery/discovery.dart`、`app/lib/main.dart`（UI 无防抖）
- **置信度**: 高——根因 1 已逐行复核（sync_engine.dart:1422）；完整时序可静态推演
- **关联**: 09-P1-2（服务端 15s 误杀，远程模式的同症状来源）

## 症状

对方下线后，在线状态先正常变成"离线"，随后又**弹出几次"在线"**，最终才稳定为离线。

## 结论

**不是故意设计。** 自动重连（指数退避）本身是设计意图，但"在线"的上报时机错误 + 重试无上限 + UI 无防抖，三者叠加产生了闪跳。

## 根因 1（主凶）：在线状态在连接真正建立之前就上报

`sync_engine.dart:1407-1424`（已复核）：

```dart
final responses = client.channel(out.stream, ...);   // 发起 gRPC 调用（惰性）
_inSub = responses.listen(...);
engine.registerSessionSink(peer.deviceId, out);      // 1422: 立即注册 → 立即广播 PeerStatusChanged(true) "在线"
out.add(engine.buildHello(peer.deviceId));           // 1423: TCP+TLS+HTTP/2 此刻才开始建连
```

`registerSessionSink` → `_registerSink` → `PeerStatusChanged(peerId, true)` 同步触发。而 gRPC 是惰性建连——**发起调用 ≠ 连上了**。对端已消失时，每次重连尝试都会先"在线"约 10 秒（`connectionTimeout: 10s`，sync_engine.dart 同文件 PeerChannel 配置），然后 `onError → _onClosed → unregisterSessionSink` → "离线"。

**修复**：把"在线"的判定从 sink 注册移到**收到对端第一个信封**（Hello/SyncAck）时——`_handleIncoming` 里首次收到该 peer 的任何数据再触发 `PeerStatusChanged(true)`；建连中状态可以显示"连接中"。

## 根因 2：重试循环无上限 + UI 无防抖，发现层超时窗口内反复闪跳

`_OutgoingSession._onClosed → _scheduleReconnect()`：指数退避 1s→2s→4s→…封顶 30s，**无限重试**，直到发现层宣告超时（`announceInterval×4 = 12s`）触发 `forceDisconnect`（littlelaw_core.dart:255）disposed 会话才停。

```
T+0    对方离开 → 离线 ✓ + 排定 1s 后重试
T+1s   重试① → "在线"❌（根因1）→ 连接死 IP 超时
T+11s  离线 ✓ → 2s 后重试
T+13s  重试② → "在线"❌ → ...
~T+12s 发现层超时 → forceDisconnect → 稳定离线 ✓
```

若 ARP 解析快速失败（IP 已无主机），单次失败仅 1-3 秒，12 秒窗口内可闪跳 4-5 次。

**修复**：(a) 连续 N 次失败后停止自动重试，等待下一次发现层宣告（`notePeerAddress`）再恢复——对方不在局域网时宣告本来就会停，重试纯属浪费；(b) UI/引擎层对状态变化加 5-10s 滞回（hysteresis）：离线后需连续在线 ≥X 秒才重新显示在线。

## 根因 3：Android 后台间歇唤醒造成"真实但短暂"的在线（跨分钟尺度闪跳）

对方手机息屏 → doze 冻结 → 心跳停 → 本端 40s 空闲清扫判离线（`_peerIdleMs`，正常）。但系统 FCM/维护窗口会**短暂唤醒 App** → 唤醒即发发现宣告（discovery 每 3s + 重绑后立即宣告）→ 本端 `notePeerAddress` → `ensureSession` 重连成功（此刻对方真醒着）→ 显示在线 → 对方再冻结 → 40s 后又离线。每次唤醒闪一次，直到系统彻底杀死 App。

**修复**：手机端配前台服务或心跳对齐 doze 窗口；本端可对"在线 < 30s 又消失"的链路做标记，连续 2-3 次后降频重连（迟滞），避免 UI 抖动。

## 根因 4（仅远程模式）：服务器 15s 误杀空闲连接

见 09-P1-2：hello 认证成功后读 deadline 仍停在 15s，空闲连接 ~15s 必被断 → 客户端重连 → presence 重新上线 → 再被杀——服务器侧连接循环直接驱动 presence 上/下线周期抖动，叠加传导到本端 UI。

## 验证方法

1. **根因 1/2**：A（桌面）、B（手机）配对在线 → B 直接关 WiFi（不退 App）→ 观察 A 的设备列表：预期复现"离线→在线→离线→在线…→稳定离线"，闪跳持续约 12 秒
2. **根因 3**：B 息屏放置 5 分钟，观察 A 的状态周期性闪跳与 Android 电池维护窗口的对应关系（`adb shell dumpsys deviceidle` 可查）
3. **修复后回归**：上述两场景状态变化各只发生一次（或带"连接中"中间态），无反复
