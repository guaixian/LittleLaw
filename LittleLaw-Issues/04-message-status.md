# 04 · 消息状态模块 —— 发送状态长期显示错误

- **优先级**: P0
- **涉及文件**: `core/lib/src/sync/sync_engine.dart`
- **置信度**: 高（状态机转移可直接推演）

## 症状

聊天时消息状态"永远是错的"：明明能送达的消息先显示失败（红色感叹号/重发按钮），过一会儿又自己变成已送达；群聊里大家都收到了，发送方却显示失败。

## 根因 A：离线 45 秒即判"发送失败"，与存储转发语义冲突

`sync_engine.dart` `_sweepPendingAcks()`：

```dart
static const _ackFailAfter = Duration(seconds: 45);

void _sweepPendingAcks() {
  final now = ...;
  for (final entry in _pendingSentAt.entries) {
    final peerId = entry.key;
    if (_sinks[peerId] != null && _sinks[peerId]!.isNotEmpty) continue; // 在线跳过
    for (final seqEntry in entry.value.entries) {
      if (now - seqEntry.value < _ackFailAfter.inMilliseconds) continue;
      final msgId = _pendingAcks[peerId]?[seqEntry.key];
      if (msgId == null) continue;
      final m = store.getMessage(msgId);
      if (m != null && m.sendState == Message.sendSending) {
        markFailed(msgId);        // ← 离线超 45s 判死
      }
    }
  }
}
```

LittleLaw 的架构是**存储转发**：消息落库 + 进 ops 表，对端上线后按游标补发，必然送达（这正是 README 宣称的 Telegram 模式）。但扫描器只要发现"无活链路 + 45 秒无 ACK"就把状态改成 `sendFailed`。

远程 WebRTC 场景链路本来就频繁断（手机 doze、网络切换），于是：

```
发送 → sending → （对端离线 45s）→ failed ❌ → （对端上线，游标 ACK）→ ok ✅
```

用户全程看到的是"发一条红一条，过会儿又全变绿"。更糟的是配了中转服务器时，消息**已经进了离线邮箱**（`_push` 里 `pushMailbox` 成功），本地却照样 45 秒后标失败——服务端明明已代收。

### 修复

- 引入三态语义：`sending（在途）/ queued（已入队待投递，含已进邮箱）/ sent（对端 ACK）`。离线且无 ACK 的消息显示"待送达"时钟图标，**不是**失败；
- `sendFailed` 只保留给真正的失败：发送方主动取消、消息落库失败等终态；
- 若保留超时判死，至少满足"邮箱投递成功"或"ops 表在"的消息豁免。

## 根因 B：群消息只追踪第一个成员的 ACK

`_fanOutGroup()`：

```dart
var firstSeq = -1;
for (final memberId in recipients) {
  final seq = store.appendOp(memberId, Op.typeMsg, ...);
  if (firstSeq < 0) firstSeq = seq;
  ...
}
// 发送状态:任一成员 ACK 即视为送达。
if (firstSeq >= 0) {
  for (final memberId in recipients) {
    _trackPending(memberId, firstSeq, proto.msgId);
    break;                          // ← 只 track 第一个成员
  }
}
```

注释说"任一成员 ACK 即视为送达"，实现却只给**第一个成员**挂了 pending 追踪。`recipients` 来自 `groupRecipients()`（建群顺序），第一个成员大概率是建群时的初始成员：

- 第一个成员离线 → 即使其他所有成员都在线且已收到，消息 45 秒后照样被判 `sendFailed`（联动根因 A）；
- 追踪的 seq 还是 `firstSeq`（第一个成员的序号空间），其他成员 ACK 的是各自序号空间的 seq，`_markDelivered(peerId, cursor)` 按 peerId 匹配，永远匹配不到没被 track 的成员。

### 修复

```dart
for (final memberId in recipients) {
  final seq = store.appendOp(memberId, Op.typeMsg, ...);
  _trackPending(memberId, seq, proto.msgId);   // 全员追踪各自的 seq
  _push(memberId, pb.Envelope(id: ..., chat: proto.deepCopy()..opSeq = Int64(seq)));
}
```

`_markDelivered` 本身就是"任一 peer 的游标覆盖该 seq 即送达"，全员追踪后语义自然成立。

## 次要问题

| 问题 | 位置 | 说明 |
|------|------|------|
| 状态回跳不撤销 UI | `markFailed` → 后续 `_markDelivered` | 失败转 ok 时 UI 靠 `MessageStateChanged` 事件刷新，确认聊天页有监听该事件并重绘（若只重绘新增消息会残留失败图标） |
| `repushMessage` 重复 op | `repushMessage()` | 重发会追加一条新 op，旧 op 仍在 ops 表，对端幂等去重无害，但 ops 表膨胀；可考虑复用原 seq |
| 45s 与心跳/看门狗参数耦合 | `_ackFailAfter` vs `heartbeatInterval`(15s) / `_peerIdleMs`(40s) | 半开链路检测本身要 40s，判死时限(45s)与之几乎重叠，处于"链路刚判死、消息也判死"的竞态带，建议判死时限 ≥ 2× 链路恢复周期 |

## 验证方法

1. **根因 A**：A 给离线的 B 发 5 条消息 → 60 秒后 A 侧应全部显示"待送达"而非失败 → B 上线 → 全部转"已送达"且 B 收到。
2. **根因 B**：建群（成员顺序 M1、M2、M3）→ M1 离线 → A 在群里发消息 → M2/M3 收到 → A 侧应显示"已送达"（任一成员 ACK）而非失败。
