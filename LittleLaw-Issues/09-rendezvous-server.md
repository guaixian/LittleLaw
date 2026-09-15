# 09 · 中转服务器（Go）与 UPnP —— 身份模型失守与配额失效

- **优先级**: P0（服务端架构级）
- **涉及文件**: `server/*.go`（auth/client/hub/mailbox/limits/push/protocol/main）、`core/lib/src/rendezvous/rendezvous.dart`、`core/lib/src/net/upnp.dart`
- **置信度**: 高，P0 与 15s 误杀已逐行复核源码

## P0

### P0-1 身份完全自声明，"TOFU"未实现——任意 deviceID 可被冒充

`auth.go:49-73` + `client.go:125`：

```go
func verifyHello(deviceID, fingerprint, certPEM, sigHex, nonce string) error {
    ... // 仅证明"签名者持有客户端自己带来的证书私钥"，指纹与该证书自洽
```

`verifyHello` 只验证签名与证书自洽。deviceId 是随机 UUID，与证书无派生关系，服务器**没有任何 `deviceID → 证书指纹` 的首次登记表**（注释宣称 TOFU 模型，但代码里没有 TOFU 存储）——实际语义是"信任任何自声明身份"。

一台恶意客户端即可全部做到：
- 声明**受害者 deviceID** → `hub.register` 把受害者真实连接踢下线（可持续 DoS）；
- 以受害者身份 `mailbox_fetch` + `mailbox_ack`：**读取并永久删除**受害者离线信箱（信封虽是 E2E 密文，删除即离线消息灭失）；
- `push_register` 覆盖受害者 FCM token（离线唤醒永久失效）；
- 冒充期间真实同伴发给受害者的 signal 被路由到攻击者；
- 订阅任意 deviceID 的 presence 并获取其 UPnP **家庭公网 IP:port**。

LAN 发现路径明确做了指纹绑定校验（littlelaw_core.dart:263-271），唯独服务器没做。

**修复**：bbolt 维护 `deviceID → fingerprint` 首见登记表，verifyHello 通过后校验一致；或 deviceId 改为 `sha256(cert DER)` 派生使绑定内生。至少先把 mailbox/push/踢线限制在指纹匹配的连接上。

## P1（7 项）

### P1-2 认证成功后读超时仍是 15s，空闲连接 ~15s 必被误杀

`client.go:108-114`（已复核）：

```go
if !c.authed {
    _ = c.conn.SetReadDeadline(time.Now().Add(authTimeout)) // 15s
    if !c.handleHello(message) { return }
    continue    // ← hello 成功后 deadline 停留在 now+15s
}
```

hello 成功后只有收到 **pong** 才续期，而首个 ping 要 45s 后才发。空闲已认证连接在最后一条消息后 ~15s 被断开；Dart 客户端恰好每 15s 轮询邮箱，与 deadline 同边界——网络抖动/GC 即触发"断开→重连"循环，presence 与信令周期性抖动。**这可能是"在线状态反复横跳"的服务端成因之一。** 修复：`handleHello` 成功后立即 `SetReadDeadline(now+pongWait)`。

### P1-3 mailbox `totalBytes` 数据竞争，全库配额非原子

`mailbox.go:120/192-196`：`Push` 的 check-then-add 依赖 bbolt 事务串行，但 `Ack` 的减法在事务外无锁执行——并发 Push/Ack 构成 read-modify-write 竞争（`go test -race` 必报），计数丢失更新可绕过 2GiB 配额。修复：互斥锁或把计数放进 meta bucket 事务内。

### P1-4 配额跨重启即失真：估算 32B/封 vs 实际最大 256KiB/封

`mailbox.go:72-88`：重启后按"每封 32 字节"估算总量（实际单封可达 ~350KB）——重启后计数几乎归零，2GiB 上限形同虚设；Ack 按真实字节数扣减，与加法不对称 → "灌满→重启→ack→再灌满"可让磁盘无限增长；不计 bbolt 页/桶开销，数十万个小桶可让实际占用远超计数。修复：启动精确遍历求和；页/桶开销计入；限制收件人桶总数。

### P1-5 deviceID/endpoint/订阅 ID 长度与格式零校验，endpoint 形成广播放大

`client.go:129-130`：endpoint 原样进入 presence 广播——冒充者携带 ~1MiB endpoint，每次上线事件向所有关注者复制 1MiB 帧，30 conn/min 重连速率下持续打满带宽。修复：hello 处校验 deviceId 为 UUID ≤64 字符、endpoint 用 `net.SplitHostPort` ≤260。

### P1-6 presence 无任何授权：任意认证连接可订阅任意设备并获取其家庭公网 IP:port

`hub.go:62-86`：无许可校验。与"服务器是瞎子"的隐私承诺直接冲突（内容盲，元数据全开且可被第三方查询）。修复：订阅需配对令牌派生的 capability；endpoint 改密文或按接收方单独分发。

### P1-7 UPnP SSDP 首响应即信：不校验设备类型

`upnp.dart:97-113`：M-SEARCH 用 `ssdp:all` 且取**第一个**响应的 LOCATION。局域网恶意主机可抢先应答 → 客户端把内网 IP 的 SOAP POST 发给攻击者（拓扑泄露），还可伪造"成功"让客户端把**攻击者 IP:port 当作自己的公网端点**上报并广播给所有同伴（同伴直连流量被导向攻击者）。修复：定向 `ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1`，校验响应 ST/USN 与 LOCATION 网段。

### P1-8 mailbox_fetch 无分页：合法限频内 ~300MB/s 内存分配放大

`client.go:198-207`：一次返回整箱（≤500 封/16MiB）单帧 JSON，200 帧/10s 窗口允许 20 次 fetch/s ⇒ 320MiB/s 序列化+GC 压力。修复：游标分页（每页 ≤50 封或 ≤1MiB）。

## P2（11 项）

| # | 位置 | 问题 | 修复 |
|---|------|------|------|
| 9 | limits.go:46-92 | 限频可绕过：IPv6 每 /128 一个桶（持 /64 即无限桶）；换连接重置消息突发额度（重连风暴维持 5 倍稳态速率）；反代后全用户共享一个桶 | IPv6 按 /64 聚合；按 deviceID 计数；可信代理配置 |
| 10 | push.go:55-66 | FCM token 无长度/格式校验，可被任意连接覆盖任意设备（联动 P0-1） | ≤4KiB + 字符集校验 |
| 11 | rendezvous.dart:351-355 | 邮箱"未知来源即 ack 删除"与 signal 的 fallback 解密不对称——配对完成与入库之间、令牌轮换、恢复场景下合法信封被**永久删除**（服务器已删无重试） | 邮箱也尝试 fallback 令牌；彻底失败延迟 ack |
| 12 | rendezvous.dart:256/398 | 客户端吞掉所有服务器 error（认证失败→无限静默重连；邮箱满对发送方不可见→活链路僵死时消息静默丢） | error 帧暴露为事件；pushMailbox 失败重试 |
| 13 | rendezvous.dart:186-194 | 重连退避无抖动——公共服务器重启全体客户端齐连（thundering herd）；`start()` 不重置退避 | ±50% 抖动；start 重置 |
| 14 | rendezvous.dart:311-341 | 信令/pair_answer 无重放防护（GCM 随机 nonce 无序号），重放旧 pair_answer 重新触发配对状态机 | AAD 加单调计数器+发送方 ID |
| 15 | upnp.dart:122-196 | HttpClient 无连接超时；`.timeout()` 只弃约不取消——恶意描述服务器永不响应则每次泄漏 socket；正则配对 serviceType/controlURL 可能绑错服务 | connectionTimeout + abort；XML 解析器按块配对 |
| 16 | upnp.dart:17/63-81 | 静态 `_lastMapping` 并发竞争；固定外端口同 NAT 两台设备必有一台失败；LeaseDuration=0 崩溃后留**永久**映射 | 实例化；冲突递增；有限租期+续租 |
| 17 | main.go:16-21 | WebSocket `CheckOrigin` 恒真——网页可消耗受害者 IP 的建连令牌（定向连接饥饿） | 生产配置 Origin 白名单 |
| 18 | auth.go:27-29 | 签名摘要 `deviceID|fingerprint|nonce` 无域分隔/长度前缀（签名协议卫生） | 长度前缀或域标签 |
| 19 | hub.go:88-98 | `watchersOfLocked` 每次上下线全表扫描且持写锁，4096 连接 × 512 订阅 ⇒ 单次 ~2M 查找，连接抖动可让 presence 全局停摆 | 反向索引 O(1) |

## 验证建议

- P0-1：用任意密钥对伪造受害者 deviceId 连服务器 hello → 订阅其 presence、fetch+ack 其邮箱、覆盖其 push token
- P1-2：两客户端建立连接后静默 20s（无聊天），观察是否周期性掉线重连
- P1-3/4：`go test -race` 跑邮箱并发；灌满邮箱 → 重启服务器 → 观察配额归零
