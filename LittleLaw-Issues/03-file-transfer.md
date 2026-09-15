# 03 · 文件传输模块 —— 远程/重试场景传输总是失败

- **优先级**: P0
- **涉及文件**: `core/lib/src/transfer/transfer.dart`、`proto/littlelaw.proto`
- **置信度**: 根因 A 高（控制流可直接推演）；根因 B 中高（并发交错需要慢链路/重试触发，逻辑上必然）

## 症状

文件传输经常失败，远程（WebRTC）模式几乎必败；失败信息偶见 `帧偏移错乱: 期望 N, 收到 M`；重试依然失败。

## 根因 A（P0）：陈旧 gRPC 地址无回退，远程设备走死路

`transfer.dart` `_doReceive()`：

```dart
final host = peer.lastHost;
final port = peer.lastPort;
// 无 gRPC 可达地址(如 WebRTC 跨网链路)→ 走信封式拉取。
if (host == null || host.isEmpty || port == null) {
  return _doReceiveViaEnvelope(peerId, msg);
}
// 否则一律走 gRPC 直连:
final ch = PeerChannel.connect(host: host, port: port, ...);
```

问题：判断条件只看**有没有**地址，不看地址**可不可达**。远程 WebRTC 对端如果曾经在同一局域网配过对，`peer.lastHost/lastPort` 里留着旧的 DHCP 地址（该 IP 可能已易主）。此后每次文件拉取都去连那个地址 → TLS 指纹校验失败 / 连接超时 → `_fail()`。UI 手动重试走同一函数、用同一陈旧地址 → **永久失败**，信封式路径（明明可用）永远不会被尝试。

### 修复

- gRPC 路径失败（连接失败/超时/指纹不匹配）后**自动回退** `_doReceiveViaEnvelope`；
- 或路由决策改为：`sync.isOnline(peerId)`（当前有活链路，含外部链路）时优先信封式，gRPC 只用于"发现层刚宣告的局域网地址"；
- 连续 N 次失败可考虑作废 `lastHost/lastPort`，等发现层刷新。

## 根因 B（P0）：fetch 协议无会话标识，重试导致发送侧双循环并发

`proto/littlelaw.proto`：

```proto
message FileFetchRequest {
  string file_id = 1;
  int64 offset = 2;   // ← 只有 fileId+offset，没有 attempt/session 标识
}
```

`transfer.dart` 接收侧 `_doReceiveViaEnvelope()` 有 30 秒停滞超时；发送侧 `_serveEnvelopeFetch()` 由 `FileFetchRequested` 事件**直接 `unawaited()` 派发，无并发去重**：

```dart
} else if (e is FileFetchRequested) {
  unawaited(_serveEnvelopeFetch(e));   // ← 同一 fileId 可能同时跑两个循环
}
```

失败链条：

1. 接收方首次拉取，慢速链路上 30s 无数据 → 超时判失败；
2. 接收方重试（发新的 `FileFetchRequest`，offset = .part 长度），同时**旧的发送循环还在等 ACK（最长 30s）**；
3. 发送侧为新请求又起一个 `_serveEnvelopeFetch` 循环 → 两个循环并发向同一接收方发 `FileData` 帧；
4. 接收侧按 fileId 路由进同一个 `dataStream`，严格校验：

```dart
if (frame.offset.toInt() != received) {
  throw StateError('帧偏移错乱: 期望 $received, 收到 ${frame.offset}');
}
```

两个循环的帧交错 → 偏移必然不连续 → 抛"帧偏移错乱" → `_fail()`。群文件多源拉取（`_receiveGroupFileMulti` 换源重试）同理触发。

### 修复

- proto 层：`FileFetchRequest` / `FileData` / `FileDataAck` 增加 `uint32 attempt`（或 `string session_id`）字段，接收侧只接受当前 attempt 的帧，旧 attempt 帧直接丢弃；
- 发送侧：`_serveEnvelopeFetch` 按 fileId 做互斥——收到新请求时先终止旧循环（可用 `Completer`/版本号自增使旧循环在下一个 await 点退出）再起新循环；
- 兼容性：attempt 缺省 0，旧版本互操作不受影响。

## 次要问题

| 问题 | 位置 | 说明 |
|------|------|------|
| 30 分钟整调用超时 | `_doReceive` gRPC `CallOptions.timeout` | 大文件 + 慢链路会整体失败，建议按剩余字节动态计算或取消整体超时只保留停滞检测 |
| 固定 8 帧 × 64KiB 窗口 | `_ackWindowFrames` + `envelopeChunkSize` | 高 RTT（TURN 中继）下吞吐被锁死（约 512KiB/RTT）；建议 RTT 自适应窗口 |
| `_ackNotifiers` 覆盖 | `_serveEnvelopeFetch` | 并发等待同一 fileId 时 `Completer` 被覆盖，先到的等待者只能靠 30s 超时退出（与根因 B 一并修复即可） |
| 失败时进度事件 `doneBytes: 0` | `_fail()` | UI 进度条会跳回 0，应回报当前已收字节 |

## 验证方法

1. **根因 A**：A、B 两设备先在局域网配对互传文件成功 → A 换到手机流量（或改 IP）→ WebRTC 链路正常聊天 → 传文件必败。修复后应自动走信封式成功。
2. **根因 B**：信封式传输中途断开 WebRTC 30 秒再恢复（或飞行模式开关），观察 `.part` 续传；修复前大概率报"帧偏移错乱"，修复后续传成功。
