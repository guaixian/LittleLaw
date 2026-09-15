# 08 · 加密与 OOB 模块 —— 密钥调度缺陷与静默数据损坏

- **优先级**: P1（无 P0，但 4 项 P1 均影响信任链）
- **涉及文件**: `core/lib/src/crypto/{file_vault,secure_codec,backup_codec}.dart`、`core/lib/src/oob/{base45,blob,lan_oob,qr_chunker}.dart`
- **置信度**: 高

## P1

### P1-1 QrReassembler 跨流混片/旧帧残留，静默产出错误载荷

`qr_chunker.dart:62-69`：帧头只有 `total`，**没有批次/流标识**，也没有整体校验。

- 两份总帧数相同的引导包帧交错扫入（多设备并排显示 QR、10 分钟窗口内重新生成 QR 长度几乎不变）→ 重组结果为两份载荷的杂糅，`complete` 照样为 true；
- 扫了一半改扫另一份同 total 序列 → `containsKey` 把新帧**静默丢弃**，最终返回**旧的有效引导包**——若旧 offer 仍在新鲜期内，会**静默配到错误的设备/指纹**。

修复：帧头加随机批次 ID（`LLQ2.<batch>.<total>.<seq>.…`）；同 seq 不同内容视为新流；末帧带全 payload SHA-256 终检。

### P1-2 Base45 字节序与 RFC 9285 相反，跨实现静默数据损坏

`base45.dart:34-41`：RFC 9285 规定三字符**低位在前**，本实现先写最高位。`"AB"` 编码为 `"8BB"`，标准实现为 `"BB8"`。解码侧与自身对称所以应用内自洽，但仓库存在 LLB1/LLB2/LLB3 多版本兼容解码——引导包跨版本/跨实现流动时值域仍合法，**不报错、静默产出错误字节**，直接作用于配对指纹和 token 通道。修复：改 RFC 顺序；或坚持私有序但换 `LLB4` 前缀并删除虚假的 RFC 声明。

### P1-3 端到端长期密钥 = QR 展示的 bearer token，无 DH/无轮换/无前向保密

`secure_codec.dart:14-16` + `rendezvous.dart:374`：

```dart
SecureCodec(String token)
    : _key = SecretKey(sha256.convert(utf8.encode('littlelaw-e2e-v1:$token')).bytes);
```

`peer.token` 直接取自 OOB 引导包——**offer 方二维码里明文展示的共享令牌**。肩窥/照片泄露/屏幕共享即拿到 token → 派生密钥**永久解密并伪造**双方经中转服务器的全部信令与邮箱流量（`pair_answer` 也走此密钥，配对入账路径随之被接管），直到重新配对。无密钥轮换、无前向保密。系统已有自签证书+ECDSA 却用对称 PSK 做消息层，身份密码学资产闲置。

修复：token 仅作配对确认；消息层改用身份密钥 ECDH（按指纹 pin 对端公钥）派生会话密钥 + 双向棘轮。

### P1-4 decryptToCache 明文缓存残留，架空 .llenc 威胁模型

`file_vault.dart:176-227`：查看附件时完整明文落在固定路径 `<dataDir>/vault-cache/<原文件名>`，仅在总量 >512MB 或退出钩子清理。**进程崩溃/强杀/断电时最多半 GB 明文永久残留**——恰是"防共享目录/网盘同步泄露"要防的场景；缓存名暴露文件元数据。修复：查看完即删或短 TTL；缓存命中校验密文指纹；评估 cacheDir 不随 dataDir 同步。

## P2（9 项）

| # | 位置 | 问题 | 修复 |
|---|------|------|------|
| 5 | file_vault.dart:230-235 | 文件级 12B 随机 nonce 只取前 8B 进 IV，后 4B 无视——无意义丢弃 32 bit 熵，同 key 同 IV 的 GCM 重用理论可能 | HKDF 派生每文件子密钥，IV 用足 12B |
| 6 | file_vault.dart:73-77/128 | 加密块边界跟随 `openRead()` 流缓冲而非声明的 1MiB；未来任何平台单次产出 >1MiB，自己加密的文件被自己判死，**明文已删无法恢复** | 加密侧显式累积固定块；解密上限仅告警 |
| 7 | file_vault.dart:122-128 | 头部无认证的总长度/块数——**尾部截断不可检测**（中段删块会 IV 错位失败，唯独尾部畅通）；文件 <17B 直接 RangeError | 头部加认证长度字段并核对 |
| 8 | file_vault.dart:162 + transfer.dart:602 | 缓存键把非法字符折叠为 `_` 且用 **String.hashCode**（32bit 可碰撞）参与标识——碰撞时 `_plaintextFor` 会把 A 会话文件明文当 B 会话的发出 | cacheKey 用 SHA-256(path‖size‖mtime) |
| 9 | secure_codec.dart:24-36 | 无 AAD、无方向/序列绑定——恶意/被入侵中转可反射密文、重放历史信令、跨上下文注入 | AAD 绑定 direction/sender/kind/seq + 接收校验 |
| 10 | backup_codec.dart:13/25-33 | PBKDF2 150k 轮偏低（OWASP 建议 600k/Argon2id）；**KDF 参数不入头**，将来调参即旧备份全毁且报"口令错误"误导 | 头部存 KDF 参数；轮数提升 |
| 11 | blob.dart:108-181 | `lzma.decode` 无解压上限（解压炸弹 OOM）；`as String?` 硬转换在字段类型不符时抛 TypeError（扫码路径未处理崩溃）；时间戳只查"过老"不查"未来"（回拨即失效）；LLB1/2 不容忍缺 `=` 填充 | 限长解压；`is` 判型；双向时间窗；容忍缺填充 |
| 12 | lan_oob.dart:44-63 | 同类健壮性缺口；fingerprint 缺失静默降级 `''` | 强制 64-hex 或报错 |
| 13 | qr_chunker.dart:13/19/33 | `isChunk` 会 trim 空格而 `parseFrame` 不认——base45 字母表含空格（注释自己警告不能 trim），带入空格的帧被**静默吞掉**；`split(chunkSize: 0)` 死循环 | 两者统一只剥 `\r\n\t`；入参断言 |

## 验证建议

- P1-1：同窗口先后展示两份同长度的分片 QR，扫描顺序交叉，观察重组出的载荷
- P1-2：用任意标准 base45 库编码 `"AB"` 与本实现互解
- P1-3：从二维码提取 token，构造 `SHA-256("littlelaw-e2e-v1:"+token)` 解密中转信箱密文
- P1-4：查看一个加密附件后强杀进程，检查 vault-cache 目录明文残留
