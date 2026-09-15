# 05 · 发现层 —— 健壮性与安全问题（含实测证据）

- **优先级**: P2（不影响基本可用性，但建议尽快加固）
- **涉及文件**: `core/lib/src/discovery/discovery.dart`
- **置信度**: 高——其中"未认证枚举"已在本局域网**实测复现**

## 实测证据（先说结论）

在 192.168.32.0/20 局域网内，一台**未配对的陌生扫描机**仅凭公开的协议常量，向运行 LittleLaw 的 Android 设备单播一个手工构造的 `DiscoveryPacket`（protobuf wire format，magic=`LLAW`、`protocol_version="1"`、`port` 填任意合法值），立即收到完整回执：

```
设备 ID  : 726c4e29-3cb5-40b5-9f91-c72d92c173ce
设备名称 : <用户自定义名称>
平台     : android
机型     : Xiaomi 2211133C
gRPC端口 : 47520
证书指纹 : 473c0fce...（完整 SHA-256）
```

即：**发现层把设备身份信息免费发送给任何询问者**，可被用于设备指纹追踪、在线状态监控、针对性攻击的信息收集。

## 问题 1：/24 硬编码，大子网漏发现

`_scanSubnet()` 与 `_broadcastAddresses()` 都按 `/24` 切分：

```dart
final parts = addr.address.split('.');
prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');   // /24 假定
...
result.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
```

实测环境是 /20（192.168.32.0/20，企业网常见）。跨 /24 的设备只能依赖组播兜底；一旦 AP/交换机不转发组播（不少企业 WiFi 默认关闭），192.168.32.x 与 192.168.33.x 的设备**互相发现不到**，定向广播（/24 的 .255）在路由器上通常也被禁。

### 修复

用接口真实子网掩码计算 CIDR（Windows `GetAdaptersAddresses` / Dart `NetworkInterface` 拿不到掩码时，可用路由表推断或直接对 `peer` 已知地址段扫描）；扫描量可控时对整个本网段做单播探测，广播地址按真实掩码计算。

## 问题 2：`timestamp_ms` 字段存在但从未校验（重放）

`_handleDatagram()` 校验了 magic / 版本 / 端口范围，但对 `timestamp_ms` 没有任何新鲜度检查；`lastSeenMs` 收到任何合法报文即刷新：

```dart
final now = DateTime.now().millisecondsSinceEpoch;
final existing = _devices[id];
if (existing != null) {
  existing.lastSeenMs = now;    // ← 重放旧报文即可续命
```

攻击者（或普通脚本）重放抓到的历史宣告报文，可以让**已离线的设备在所有人 UI 里永远"在线"**；配合 04 号文档的在线状态语义，还会误导同步引擎持续向幽灵设备排队。

### 修复

- 校验 `|now - timestamp_ms| < 窗口`（如 ±60s，容忍设备时钟偏差；可记录每设备偏差自适应）；
- 超窗报文丢弃并计数，异常高频可触发告警/限流。

## 问题 3：宣告/回执明文且信息全量

组播宣告每 3 秒一次，明文 protobuf 广播 `device_id / device_name / platform / device_model / cert_fingerprint / port`；回执逻辑对**任何**未配对探测者返回同样的全量信息（见实测证据）。

局域网内的被动观察者（无需发送任何包）即可枚举所有 LittleLaw 用户、追踪上线规律、关联设备身份。

### 修复（分级披露 + 签名）

1. **签名**：`DiscoveryPacket` 增加身份密钥 ECDSA 签名字段，接收方验签后才展示/回执——伪造设备泛滥（污染他人设备列表/DoS UI）同时被挡住；
2. **分级披露**：对未配对的询问者只回 `{device_id, device_name}`；`platform / device_model / cert_fingerprint / port` 等敏感字段仅在 TLS 建连后（或配对后）提供；
3. **可选加密**：已配对设备间的宣告可用配对令牌派生密钥加密，向陌生观察者隐藏身份。

## 问题 4：其他小项

| 问题 | 说明 |
|------|------|
| 回执限频 3s/host | `_replyCache` 按 host 限频，但宣告仍每 3s 组播一次——移动端耗电；建议空闲时指数退避（3s→15s→30s） |
| 无端口扫描面收敛 | 47520 固定 + WebRTC 三个随机 TCP 监听口（flutter_webrtc ICE）常开；无通话时可关闭 ICE 服务型监听，减小指纹面 |
| 组播失败降级静默 | `joinMulticast` 失败被吞（注释称"不致命"），建议至少在设置页展示"当前网络组播被禁，发现依赖子网扫描"提示，联动问题 1 |

## 验证方法

- 问题 1：在 /20 网段两端（不同 /24）各放一台设备、关闭网络组播，确认互相发现不到；按真实掩码扫描修复后可发现；
- 问题 2：`tcpdump` 抓一份宣告报文，用 `tcpreplay`/脚本循环重放，观察设备离线后 UI 是否持续显示在线（修复前：是）；
- 问题 3：使用本仓库 issue 附带的探测脚本（构造 DiscoveryPacket 单播）对任一在线设备探测，修复前返回全量信息，修复后仅返回最小集。
