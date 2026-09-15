# 02 · 配对 UX 时序 —— 成功提示延迟弹出 & 聊天页重复跳转

- **优先级**: P1（功能正确，体验混乱）
- **涉及文件**: `app/lib/webrtc_link.dart`（`start()` / `_armChannel` / `acceptAnswer`）、`app/lib/main.dart`（`HomeShell._rtcSub`）、`app/lib/remote_pair_page.dart`（`_gotoChat`）
- **置信度**: 高（事件流时序可静态推演）

## 症状

配对完成后立即进入了聊天界面，**过了几秒**才弹出"远程链路已建立/配对成功"提示；期间聊天页还会莫名闪一下（被重建）。ICE 慢的公网环境里延迟可达十几秒，中间还可能夹一条"远程链路已断开"（联动 01 号文档的 bug）。

## 时序还原（受邀方 B 扫码为例）

```
B 扫码 → joinInvite() 配对入账
   ├─ toast '应答已自动回传,等待链路建立'     ← 立即
   └─ _gotoChat() → 跳进聊天页               ← 立即（RemotePairPage 自己跳的）
        ↓ 数秒后（ICE + DTLS + LinkAuth 完成）
   └─ toast '远程链路已建立: X'              ← 用户看到的"迟到的配对成功"
      同时 popUntil(isFirst) + push ChatPage  ← 聊天页被重建（闪一下）
```

## 根因 1：假触发 —— 链路未建立就广播"已建立"

`webrtc_link.dart` `start()`：

```dart
_answerSub = engine.answerDeliveries.listen((blobText) async {
  try {
    final peer = await acceptAnswer(blobText);
    _linkEvents.add(WebRtcLinkEvent(peer.deviceId, true));   // ← 过早触发
  } catch (e) { ... }
});
```

`acceptAnswer()` 内部只做了 `setRemoteDescription` + `addCandidate` + `_armChannel(...)`。而 `_armChannel` **仅注册回调即返回**，ICE 打洞 / DTLS 握手 / LinkAuth 鉴权均未发生。此刻广播"链路已建立"，`HomeShell._rtcSub` 收到后弹 toast 并跳转聊天页——**报"已建立"的瞬间链路其实还在连**。

## 根因 2：真触发再来一次 —— 同一连接周期 `true` 事件发两次

数秒后链路真正建立、LinkAuth 校验通过时，`_armChannel` 内部**再次**发送：

```dart
authed = true;
sink = engine.attachExternalTransport(...);
_links[peer.deviceId] = _ActiveLink(...);
_linkEvents.add(WebRtcLinkEvent(peer.deviceId, true));   // ← 第二次 true
```

而 `main.dart` HomeShell 对**每次** true 事件执行全套动作：

```dart
_rtcSub = rtcManager?.linkEvents.listen((e) {
  ...
  showToast(e.connected ? '远程链路已建立: $name' : '远程链路已断开: $name', ...);
  if (e.connected && peer != null) {
    nav.popUntil((route) => route.isFirst);     // 弹掉用户正在看的页面
    nav.push(MaterialPageRoute(                 // 重新 push，ChatPage 整页重建
        builder: (_) => ChatPage(peer: peer, engine: _engine!)));
  }
});
```

结果：toast 迟到 + 聊天页重复 push/重建。跳转入口还有第三个（`RemotePairPage._gotoChat`），导航行为由两个互不知情的模块竞争。

## 修复建议

1. **删除 `_answerSub` 里的假触发**（`webrtc_link.dart`）——"链路已建立"的唯一权威来源应是 `_armChannel` 中 LinkAuth 通过的那一刻。`acceptAnswer` 成功只需静默入账。
2. **`HomeShell._rtcSub` 导航去重**（`main.dart`）——跳转前判断当前栈顶是否已是该 peer 的 ChatPage：是则只更新状态不重复 push；或改用 `pushReplacement`。
3. **语义拆分**——把两个事件区分开：
   - "配对成功"（入账完成，同步事件）：由配对页自己跳聊天页、立即 toast（现有 `RemotePairPage` 行为，保留）；
   - "链路已建立"（异步网络事件）：只让在线徽标变绿/状态行刷新，**不弹 toast、不抢导航**。

   现在 `linkEvents` 把两件事压进同一个布尔流，UI 无法区分，是时序混乱的根源。

## 验证方法

修复后预期时序：扫码 → "已与 X 配对"（立即）→ 进聊天页（立即）→ 数秒后对方头像安静地变"在线"，全程只弹一次成功提示、聊天页不闪烁。
