# 01 · WebRTC 链路模块 —— 中转模式下链路无法建立（对方永远不显示在线）

- **优先级**: P0
- **涉及文件**: `app/lib/webrtc_link.dart`
- **置信度**: 高（代码逻辑推演可证明，不依赖运行时假设）
- **影响版本**: main 分支（2026-09 分析时点）

## 症状

WebRTC 模式（跨互联网/经中转服务器信令）配对成功后，对方**永远显示离线**；`远程链路已建立` 提示从不出现，或短暂出现后立即断开。局域网二维码直连模式不受影响。

## 根因：answerer 的 ICE 候选被全部丢弃

`_onRendezvousSignal()` 的 'answer' 分支与 'ice' 分支存在路由表竞态：

```dart
} else if (kind == 'answer') {
  final pending = _pendingRtc.remove(peerId);   // ← 从路由表移除
  if (pending == null) return;
  pending.trickleTimer?.cancel();
  await pending.pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  for (final c in candidates) {
    await pending.pc.addCandidate(_candidateFromCompact(c));   // ← candidates 恒为空
  }
  _armChannel(pending.dc, pending.pc, peer);
} else if (kind == 'ice') {
  final target = _pendingRtc[peerId]?.pc ?? _rendezvousAnswerers[peerId];
  //                              ↑ 已被 remove     ↑ offerer 侧本就没有该 peer
  if (target != null) { ... }
}
```

完整死锁链条：

1. answerer 发送 'answer' 时，SDP 被 `_stripInlineCandidates()` 剥掉全部 `a=candidate` 行，且 `candidates: const []` —— **answer 消息里没有任何候选**；
2. answerer 的候选随后作为独立 'ice' 帧每 250ms 补发（trickle）；
3. offerer 处理 'answer' 时执行 `_pendingRtc.remove(peerId)`；
4. 之后到达的所有 answerer 'ice' 帧，在 offerer 侧查 `_pendingRtc[peerId]`（已删）和 `_rendezvousAnswerers[peerId]`（该表只在**自己作为 answerer** 时写入）——**两处都为 null，候选被静默丢弃**；
5. offerer 没有对方任何 ICE 候选 → ICE 连接在数学上不可能建立 → DataChannel 永不开 → `attachExternalTransport` 永不调用 → `PeerStatusChanged(true)` 永不触发 → **永远离线**。

信令经同一个 WebSocket 传输保序，'answer' 必然先于其 'ice' 帧到达，所以这不是概率问题，是 **100% 复现**。

## 次要问题（同文件）

### A. 己方候选可能中途停止发送

'answer' 分支收到应答即 `pending.trickleTimer?.cancel()`。若此时 offerer 自己的 ICE 收集尚未完成（公网 STUN 慢是常态），flush 定时器被取消后，**后续收集到的候选永远不再发送**。收到 answer ≠ 收集完成，两者被错误等同。

### B. `_armChannel` 不检查通道当前状态

`onDataChannelState` 只在状态**变化**时触发。若注册 handler 前 DataChannel 已经 Open（快速路径下可能），`opened` 永远为 false → 我方 LinkAuth 永远不发 → 双方 10 秒鉴权超时 → teardown。应在武装时检查 `dc.state`，已 Open 则立即发送 LinkAuth。

### C. 中转重连后无主动重连驱动

`_rcStateSub` 里注释"重连成功：快照里的在线设备由 presence 帧驱动，无需额外动作"。这依赖服务端在（重）订阅时推送 presence 快照。若服务端只在状态**变化**时推送，断线重连后永远不会有事件驱动 `_offerViaRendezvous`，链路无法自动恢复。建议：重连成功后主动拉取在线快照或对所有已配对 peer 触发一次连接尝试。

### D. Android 后台冻结导致状态横跳

`_extStaleMs = 120s` 看门狗 vs 手机 doze 冻结 Dart 定时器（代码注释自己也承认"心跳停发可达分钟级"）。根治需要 Android 前台服务（FOREGROUND_SERVICE_DATA_SYNC），或至少文档说明后台限制。

## 修复建议

**P0 主修复**（三选一，推荐 1）：

1. `WebRtcLinkEvent(true)` 的权威时刻是 `_armChannel` 里 LinkAuth 通过之时，在此之前 pc 必须保持可路由。最小改动：'answer' 分支不 remove，改为在 `_armChannel` authed 成功 / teardown 时清理；或新增 `_established[peerId] = pc` 供 'ice' 路由兜底：

```dart
} else if (kind == 'ice') {
  final target = _pendingRtc[peerId]?.pc
      ?? _rendezvousAnswerers[peerId]
      ?? _links[peerId]?.pc;          // ← 新增：已建连链路也接受补发候选
  ...
}
```

2. answerer 等 ICE 收集完成（`onIceGatheringState == complete` 或固定窗口）后再发 'answer'，并把候选内联进 SDP（放弃 strip）。
3. offerer 收 'answer' 后不处理任何 trickle，answerer 侧不启用 trickle（全量内联）——牺牲建连速度换正确性。

**配套修复**：
- 'answer' 分支不再 `cancel()` trickleTimer，只在 `onIceGatheringState == complete` 里取消（同 answerer 侧逻辑）；
- `_armChannel` 开头增加 `if (dc.state == RTCDataChannelOpen && !opened) { opened = true; /* 立即发 LinkAuth */ }`；
- rendezvous 重连成功后主动触发一次全量 offer/快照拉取；
- Android 端评估前台服务。

## 验证方法

两台设备分别用手机流量（或不同网段），配置同一中转服务器，走"创建远程邀请 → 对方扫码"流程配对。修复前：`linkEvents` 无 true 事件（或 10s 后 false）；修复后：数秒内 toast"远程链路已建立"且双方在线徽标点亮。可在 `_onRendezvousSignal` 临时打印每个 'ice' 帧的 target 是否为 null 快速确认根因。
