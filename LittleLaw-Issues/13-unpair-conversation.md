# 13 · 解绑流程 —— 会话残留不清理（Windows 桌面实测）

- **优先级**: P1
- **涉及文件**: `core/lib/src/pairing/pairing.dart`、`core/lib/src/store/store.dart`、`core/lib/littlelaw_core.dart`、`app/lib/main.dart`、`app/lib/adaptive_shell.dart`
- **置信度**: 高——A/B 已逐行复核
- **关联**: 07-P2-8（单边解绑传播）、10-P2-11（右栏空白无关闭）

## 症状

Windows 上给对方发了消息，之后解绑配对——**会话依然显示在列表里**，没有按预期移除，也没有"已解绑"的墓碑标记。

## 根因 A（主凶）：解绑路径不发送任何事件，桌面会话列表不刷新

`pairing.dart:181-220`：`_wipePeer()` 在服务端 `unpair`（188 行）和客户端 `unpairWith`（219 行）都会执行本地清理，但**两个路径都不调用 `_notifyPeersChanged()`，也不发任何 `EngineEvent`**。

对比：`_notifyPeersChanged()` 在配对全流程被调用 6 次（159/273/343/378/442/476 行），唯独解绑一次都没有。

后果链：
- 桌面壳 `adaptive_shell` 的会话列表靠 `engine.events` 驱动重建 → 解绑后无事件 → **残留会话一直显示**，直到别的设备发来消息等无关事件、或重启
- 唯一刷新的是解绑按钮所在的 `DevicesPage`（main.dart 里手动 `setState`）——所以移动端看不出问题，**Windows 桌面三栏的会话中栏必然复现**
- 被解绑的**对方** UI 同样无事件，对端不刷新
- 点击残留会话 → `_activeKey` 指向已删除的 peer → `_rightPane` 返回空白 `SizedBox.shrink()`，**无关闭按钮**（与 10-P2-11 群解散同款缺陷）

**修复**：`_wipePeer()` 末尾调用 `_notifyPeersChanged()` 并发一个新事件（如 `PeerRemoved(deviceId)`）；桌面壳收到后刷新会话列表、若 `_activeKey == deviceId` 则清空右栏。

## 根因 B：clearConversation 只删消息，不删会话行——孤儿数据

`store.dart:464-466`：

```dart
void clearConversation(String convId) {
  _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
}
```

对比 `deleteGroup`（store.dart:729-730）同时删 `messages` **和** `conversations` 两张表。`_wipePeer` 调的是 `clearConversation` → **conversations 表留下孤儿行**。当前桌面会话列表从 messages 表推导所以看不见孤儿，但：
- 数据库脏数据持续累积；
- 任何未来基于 conversations 表的 UI/查询（会话设置、草稿、置顶）都会显示空会话；
- 与 deleteGroup 的行为不一致本身就是缺陷。

**修复**：`clearConversation` 同时 `DELETE FROM conversations WHERE conv_id=?`（保留一个带 force 参数的变体给"清空消息但保留会话"的场景）。

## 根因 C（对方屏幕上的残留）：单边解绑传播失败

对方离线时 `unpairWith` 的通知失败被 `catch (_)` 吞掉（pairing.dart:214-215，详见 07-P2-8）——**对方的 peers 表、会话、中转订阅永久残留**，UI 永远显示已配对。用户看到的"解绑了还会话还在"如果发生在对方设备上，就是这条路径。

## 根因 D：解绑不 forceDisconnect，已删除的 peer 还显示"在线"

`_wipePeer` 不调用 `sync.forceDisconnect(deviceId)`——sink/session 残留到对端下次 RPC 触发 unauthenticated 错误才 fatal 断开，期间 `isOnline(已删除peer)` 仍为 true。

## 设计缺口：没有墓碑会话（与用户预期的差距）

用户预期"移除会话并标记为墓碑（含解绑信息）"。当前是 Telegram 式双端静默全删——**一旦对端离线收不到通知（根因 C），全删模型必然单边残留且无任何解释**。

**建议产品方案**：解绑时保留一条墓碑会话（系统消息："已与 X 解除配对，聊天记录已删除"），带"清除"按钮。墓碑随下次配对覆盖或手动清除。这同时解决了 C 的可观察性——对端重连失败时至少能看到关系已终止的说明。

## 验证方法

1. 根因 A：Windows 桌面，A 与 B 互发消息 → A 在设备页解绑 B → 会话中栏 B 的条目依然在（不重启不下线）→ 点击该条目右栏空白无关闭按钮
2. 根因 B：解绑后检查 `conversations` 表——对应 convId 行仍存在
3. 根因 C：B 离线时 A 解绑 → B 上线后 B 侧仍显示 A 已配对、会话完整（且 B 的消息永远发不出去，无提示）
