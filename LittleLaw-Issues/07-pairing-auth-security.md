# 07 · 配对/认证/传输层安全 —— 3 个可永久劫持会话的 P0

- **优先级**: P0（安全）
- **涉及文件**: `core/lib/src/pairing/pairing.dart`、`core/lib/src/transport/auth.dart`、`core/lib/src/transport/transport.dart`、`core/lib/src/identity/identity.dart`
- **置信度**: 高，P0-1/P0-2 已逐行复核源码

## P0

### P0-1 tap 一碰/一扫配对完全无 MITM 防护，可被永久劫持

`pairing.dart:451-463`（服务端 `pairWithTap` 412-448 同样无防护）：

```dart
Future<PairResult> pairViaTap(String host, int port, String tapToken) async {
  final ch = PeerChannel.connect(host: host, port: port);   // ← 无 pinnedFingerprint，TOFU
  ...
  if (observed == null || observed != resp.responder.certFingerprint) {
    return PairResult.rejected('fingerprint mismatch, possible MITM');
  }
```

tap 流程是唯一**无人工核验**（免 PIN）的配对路径，而 QR/NFC 载荷里只有 host/port/token，**不含响应方证书指纹**。`observed` 与 `resp.responder.certFingerprint` 都由 TLS 终结者控制——MITM 让二者相等即可通过校验。

**攻击**：局域网 ARP 欺骗，MITM 用自签证书终结 TLS（TOFU 无条件接受），把 `TapPairRequest` 原样转发给真设备 → 真设备验令牌通过并返回会话令牌 T → MITM 给扫描方回一个"deviceId 是真设备、指纹是自己"的响应 → 校验通过。受害者本地存储 `(真设备ID, MITM指纹, T)`——**此后所有连接永久 pin 到攻击者证书**，E2E 加密从配对起即被穿透，用户无任何可见异常。

**修复**：QR/NFC 载荷嵌入响应方证书指纹（或哈希），`pairViaTap` 以 `pinnedFingerprint` 连接；或 tap 成功后强制一轮 SAS 确认。

### P0-2 TLS 指纹 pinning 可被"能通过系统校验的证书"静默绕过

`transport.dart:37-55`：

```dart
bool onBadCertificate(X509Certificate cert, String authority) {
  final fpr = sha256.convert(cert.der).toString();
  self._observedFingerprint = fpr;
  if (pinnedFingerprint == null) return true;
  return constantTimeHexEquals(fpr, pinnedFingerprint);
}
...
credentials: ChannelCredentials.secure(
  onBadCertificate: onBadCertificate,   // 注释称"跳过系统根校验"——实际不会
```

dart:io 的 `onBadCertificate` 回调**只在内置校验（系统信任根 + 主机名）失败时才被调用**，代码注释的假设是错的。正常自签对端永远走回调所以功能正常；但 MITM 出示一张**能通过默认校验**的证书时回调根本不执行，pinning 被完全跳过。触发条件不罕见：企业/学校管理设备预装企业根 CA；Let's Encrypt 2025 起支持为 IP 签发证书。

**后果**：TOFU 配对路径会因 `observed == null` fail-closed；但 **pinned 路径（所有消息通道、unpairWith）在发出 RPC 前从不检查 `observedFingerprint`**，gRPC 元数据在 RPC 开始即发送 → `ll-token` 会话令牌直接交给攻击者 → 完全冒充。

**修复**：每个 pinned 通道在握手完成后、首个 RPC 前强制校验 `observedFingerprint == pinnedFingerprint`（null 即失败）；或用 `SecurityContext(withTrustedRoots: false)` 承载 pinning。

### P0-3 响应方在发起方核验指纹之前即提交信任并签发令牌

`pairing.dart:146-164`（服务端提交点）/ `256-259`（客户端事后校验点）：

服务端在用户点"同意"后**立即入库、立即把会话令牌发给 TLS 对端**；发起方的指纹核验发生在服务端入库**之后**，且服务端对校验失败毫不知情、不回滚。

**攻击**：MITM M 截获 A→B 配对：M 忠实转发双方真实指纹 → A、B 屏幕上 PIN **完全一致**，SAS 核对通过 → B 入库 `peer(A_id, A_fpr, T)` 并把 T 返回给 M → A 侧随后发现指纹不匹配而放弃，但 **B 已提交**。M 此后凭 `(A_id, T)` 通过 `Auth.verify` **永久冒充 A**。PIN 配对防 MITM 的设计在提交时序上被整体架空。

**修复**：两阶段提交——响应方先暂存，发起方校验指纹后回发 confirm（用双方指纹派生的 HMAC 绑定），响应方收到 confirm 才落库；或令牌以双方指纹+随机数派生，纯转发者无法构造。

## P1

### P1-4 deliverAnswerTo 明知对端指纹却不 pin；offer 令牌可被截获注入

`pairing.dart:526-534`：answer 回传连接不传 `pinnedFingerprint`（指纹明明已在手），把 offer 令牌（共享秘密）发给任意 TLS 终结者。MITM 截获令牌后可直接向真实邀请方 `deliverAnswer`（服务端只验令牌回显）注入伪造 answer，`acceptRemoteAnswer` 把攻击者的 deviceId/指纹入库为可信节点。修复：回传必须 pin；令牌验后即焚；answer 与 offer 密码学绑定。

### P1-5 OOB 邀请令牌兼任长期会话令牌：QR 泄露 = 永久凭据

`pairing.dart:338/373`：offer 令牌既是 10 分钟邀请凭据，又被双方存为**长期会话令牌**（另见 08 号文档 P1-3：它还是 E2E 密钥材料）。QR 被拍照/截屏即永久冒充。修复：邀请令牌与配对后令牌分离，配对完成经 pinned 信道换发新令牌。

## P2（8 项）

| # | 位置 | 问题 | 修复 |
|---|------|------|------|
| 6 | pairing.dart:109-119 | 配对无速率限制（弹窗骚扰/占满 3 个 pending 槽 DoS）；冒充 deviceId 可定向顶掉他人挂起请求；容量检查在 stale 淘汰**之前**，顺序颠倒 | 先淘汰再查容量；按源限速 |
| 7 | pairing.dart:124-141/169-179 | requestId 客户端可控：同 ID 静默覆盖，`respond()` 会批准**覆盖者**的事件（混乱代理）；`cancelPair` 只比对自报字段可取消他人请求 | requestId 服务端生成或碰撞即拒；覆盖前 complete 旧事件 |
| 8 | pairing.dart:214-219 | 对端离线时 unpair 只清本地：对端信任条目+中转订阅永久残留，UI 永远显示"已配对" | pending-unpair 标记，重连时下发 |
| 9 | pairing.dart:148-158/431-441 | 已配对 deviceId 重新配对时**静默替换指纹/令牌**，无"指纹已变化"告警——一次误点同意即身份劫持 | 指纹不一致时拒绝或强制先 unpair |
| 10 | pairing.dart:545-551 | `lastHost` 取自客户端完全可控的 `:authority` 元数据，构成受控连接误导 | 从连接层取真实地址 |
| 11 | pairing.dart:238-281 | `requestPairWith` 异常路径不清理 `_outgoingRequests`，残留过期条目 | 移入 finally |
| 12 | pairing.dart:363 | 令牌回显用普通 `!=`，非常量时间（同文件 511 行却用了 `constantTimeEquals`） | 统一常量时间比较 |
| 13 | identity.dart:63-131 | 私钥明文落盘无权限收紧、三文件非原子写——崩溃在写之间 → 下次启动**静默重新生成身份**，全部配对失联；无实例锁 | temp+rename 原子写；缺件进显式恢复流程 |

## 验证建议

- P0-1/P0-3：测试环境用 mitm-proxy + 自签证书模拟 ARP 欺骗场景，观察 tap 配对与 PIN 配对中受害者入库的指纹
- P0-2：在预装企业根 CA 的设备上，让 MITM 出示 CA 签发的证书连 47520 端口，观察 pinned 通道是否无告警通过
