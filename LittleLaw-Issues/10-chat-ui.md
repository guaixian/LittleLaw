# 10 · 聊天 UI —— 桌面壳显示错会话（P0）与 15 项功能缺陷

- **优先级**: P0（1 项）
- **涉及文件**: `app/lib/chat_page.dart`、`app/lib/adaptive_shell.dart`、`app/lib/group_info_page.dart`、`app/lib/forward_picker.dart`、`app/lib/search_page.dart`
- **置信度**: 高，P0 已复核（两处 ChatPage 构造均无 key，`_ChatPageState` 无 `didUpdateWidget`）

## P0

### P0-1 桌面三栏切换会话时复用旧 ChatPage State —— 显示错会话的消息

`adaptive_shell.dart:762-781`：

```dart
final key = _activeKey!;
...
return ChatPage(peer: peer, engine: engine, embedded: true, ...);   // ← 无 key
```

`_activeKey` 从会话 A 切到 B 时，新旧 widget 同类型、无 key → `Widget.canUpdate` 为真 → **State 被复用**。`initState` 不重跑，`_messages/_selection/_transfers/_online` 全是 A 会话的数据，顶栏却读 `widget.peer/group`（已是 B）。

**结果：标题显示 B、消息列表显示 A 的内容**，`markRead`/发送目标却是 B；B 是空会话时错乱持续存在。群↔群、1:1↔1:1、群↔1:1 全部命中。

**修复**：`ChatPage(key: ValueKey(_activeKey))`；或在 `_ChatPageState.didUpdateWidget` 中比较会话变化后重载消息并重置全部状态。

## P1

### P1-2 语音气泡状态机：暂停后永远无法恢复，播完后无法重播

`chat_page.dart:1905-1928`：`_playing` 只被置 true 从不置 false，也没监听 `player.stream.completed`。(a) 点一次暂停后图标恒为"暂停"，再点执行的还是 `pause()`——**永远无法续播**；(b) 播完后 `_playing` 仍为 true，点击仍是 pause——**无法重播**；(c) 多个语音可同时播放，无互斥。修复：以播放器状态流驱动；completed 时重置；播放前互斥。

### P1-3 GroupInfoPage 事件订阅泄漏

`group_info_page.dart:22-26`：`engine.events.listen(...)` 返回的订阅被丢弃，每次打开群资料页永久泄漏一个订阅 + 整个 State 闭包链。修复：存字段，dispose 中 cancel。

### P1-4 无分页：超过 200 条的历史消息在聊天页永远不可见

`chat_page.dart:81/116/125`：`loadMessages` 默认 `limit=200`，引擎已提供 `beforeLamport` 游标但 UI 从不传、也没有滚顶加载逻辑。**search_page 搜到旧消息点进去，ChatPage 里根本不显示那条**（跳转等于失效）。修复：监听滚动接近顶部时分页拉取 + 偏移修正。

### P1-5 每个 TransferProgress 事件触发全量 DB 重载 + 整页 setState

`chat_page.dart:121-127`：core 层每 1MiB（gRPC）或每帧（信封）发一次 progress，每次都"全量消息 SQL + 整页重建"；4GB 文件 ≈ 4000 次。`MessageStateChanged`（15s 扫描）同理。`_transfers` 只增不删。修复：progress 只更新 `_transfers` 定向重绘，消息列表不重载；完成态移除；节流。

### P1-6 窗口宽度跨 850px 阈值时桌面壳整体销毁，全部状态丢失

`main.dart:426-431`：拖动窗口/最大化/分屏跨阈值即在 `AdaptiveHomeShell` 与移动端 Scaffold 间整棵替换——打开的 ChatPage（草稿、多选、录音态、`_activeKey`）全部丢失。修复：状态提升到 HomeShell 之上，或两棵子树 Offstage 共存。

## P2（10 项）

| # | 位置 | 问题 | 修复 |
|---|------|------|------|
| 7 | chat_page.dart:133-140 | dispose 中 `stop()` 未完成即 `dispose()` recorder（平台异常+录音可能未落盘）；正常停止后 recorder 从不释放 | `stop().whenComplete(dispose)`；总释放 |
| 8 | chat_page.dart:1637-1661 | 图片气泡 FutureBuilder 的 future 在 build 中反复创建——每次 setState 闪 spinner + 重复 IO（叠加 P1-5 肉眼可见闪烁） | 按 msgId 缓存 future |
| 9 | chat_page.dart:1629-1631 | 媒体气泡忽略 DB 里 `fileState==transferring`：传输开始于打开页前/中途重启 App 时只显示黑占位（与文件卡片口径不一致） | `transferring \|\| fileState==transferring` |
| 10 | chat_page.dart:90-92 | 多选时对端删除消息只处理 `clearAll`——选中集残留幽灵 id，删除会把不存在的 id 传给引擎 | `_selection.removeAll(e.msgIds)` |
| 11 | chat_page.dart:85-114 | 不处理 GroupSynced/ProfileUpdated：顶栏群名/对方昵称是构造时快照不刷新；群解散后桌面右栏永久空白无关闭按钮 | 监听事件实时取；shell 校验 key 有效性 |
| 12 | adaptive_shell.dart:139-142 | 切到"连接/设置"页强制 `_activeKey = null`——点一下设置再回来，聊天面板变回占位页，草稿丢失 | 保留 `_activeKey` |
| 13 | adaptive_shell.dart:38-49/210-211 | 桌面壳每类事件全量 setState + build 中重查 conversationSummaries——群消息风暴明显掉帧 | 事件子集定向重建；摘要缓存 |
| 14 | group_info_page.dart:22-34 | 成员在线点只在 GroupSynced 时重绘（不监听 PeerStatusChanged）→ 绿/灰点长期错误；rename 的 TextEditingController 泄漏 | 补事件；ctrl dispose |
| 15 | search_page.dart:26-30/91 | 每击键同步全库 LIKE 查询（UI 线程卡顿）；Enter 双跑；跳转目标已解配/解散时静默无效 | 300ms 防抖；目标缺失给 toast |
| 16 | forward_picker.dart:92-110 | 桌面端转发后 push 全屏 ChatPage 覆盖三栏外壳（关闭后嵌入面板并非目标会话） | 桌面壳走 `_activeKey`，仅移动端 push |

## 验证建议

- P0-1：桌面端宽屏，左侧点开会话 A（有消息）→ 再点会话 B（空会话）——右栏标题 B、内容 A
- P1-2：发两条语音，点播放 → 暂停 → 再点（无法续播）；等播完 → 再点（无法重播）
- P1-4：会话里累积 201+ 条消息（可用测试脚本灌入），观察旧消息是否可达；搜索第 100 条消息并点击跳转
