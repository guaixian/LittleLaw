# LittleLaw — 局域网端到端加密多端通讯

NoServer 架构:没有中心服务器,**每个设备既是服务端又是客户端**。
手机(Android/iOS)与电脑(Windows/macOS/Linux)互相发现、配对后直接通讯:
聊天、任意复制粘贴、文件传输,全部走 TLS 加密 + Protobuf(gRPC)。

## 三种连接场景

| 场景 | 通道 | 配对方式 |
|---|---|---|
| **同一局域网** | UDP 组播/广播/子网扫描自动发现 + gRPC over TLS | 设备列表 PIN 码;或「碰一碰/扫一扫」免 PIN |
| **附近无路由器** | 热点直传(一台开热点另一台加入,即同局域网) | 加入热点后同上 |
| **跨互联网** | WebRTC DataChannel(DTLS)点对点打洞 | OOB 引导包(二维码/文本)offer/answer 往返 |

### OOB 引导(带外认证)

配对载荷经物理/人工通道传递,指纹即信任锚:

- **NFC 一碰**(Android 双向;Android→iPhone 单向读取):HCE 模拟 NDEF 标签
  携带一次性 tap 令牌,物理触碰 = 最强带外认证,**免 PIN**;
- **二维码一扫**(全平台):同一载荷的二维码形态,桌面显示、手机扫;
- **复制粘贴引导包**(远程):WebRTC SDP/ICE 信令的载体,offer/answer 双向
  文本经任意 IM 交换,令牌回显校验防错配。

### 热点直传细节

- Android 8+:程序化 `LocalOnlyHotspot`(不耗流量),生成随机 SSID/密码 +
  WiFi 二维码;Android 10+:程序化加入(`WifiNetworkSpecifier`),加入后
  引擎流量自动绑定到热点网络;
- iOS:系统限制无法程序化开热点,UI 引导手动开「个人热点」;
- 桌面端:系统热点/互联网共享功能,UI 提供各系统操作指引。

### WebRTC 跨互联网的现实约束(诚实声明)

- 打洞依赖 STUN(设置页可配,默认国内外三组);
- 运营商 CGNAT(手机流量几乎必中)下打洞**概率性失败**,兜底只能 TURN 中继
  (设置页可配自建中继地址/凭据)——这是物理现实,与微信走腾讯服务器同理;
- DataChannel 为可靠有序 SCTP,文件经信封通道传输(64KiB 帧 + 断点续传 +
  SHA-256 校验),与 gRPC 数据面共用同一同步引擎。

## 界面与主题

- **统一设计系统**:圆角卡片 + 渐变点缀 + Material 线性图标(无 emoji),
  所有页面共享同一套组件语言(`app/lib/theme/app_theme.dart`);
- **底部导航三段式**:设备(配对/发现卡片流)/ 连接(四种连接方式)/ 我的
  (身份卡、主题、设置);
- **主题皮肤**:6 套内置配色(薄荷汽水/橘子汽水/蓝莓气泡/葡萄碎冰/白桃乌龙/
  青提茉莉),浅色/深色/跟随系统,「我的」页可视化切换,本地持久化;
- 聊天页:渐变我方气泡、时间分隔条、长按/右键上下文菜单、多选批量删除、
  图片内联缩略图与全屏缩放预览、视频全屏播放(media_kit)。

## 架构

```
┌──────────────────── Flutter UI(app/)—— 五端同一份 ───────────────────────┐
│  设备列表 / 配对PIN弹窗 / 一碰一扫 / 热点直传 / 远程WebRTC / 聊天页          │
├──────────────────── 核心引擎(core/,纯 Dart,无 UI 依赖) ──────────────────┤
│  discovery   UDP组播(239.255.42.99:47521) + 定向广播 + /24 子网扫描      │
│  pairing     ①TOFU+6位PIN(SAS) ②PairWithTap 一次性令牌 ③OOB引导包      │
│  transport   固定TCP 47520,gRPC over TLS,服务端证书指纹 pinning          │
│  sync        1:1会话 ops日志 + Lamport时钟,断线重连按游标补发,            │
│              删除=墓碑op双端硬删(Telegram模式);                           │
│              attachExternalTransport: 外部链路(WebRTC)可插拔              │
│  transfer    gRPC拉取式(1MiB chunk) ‖ 信封式(64KiB,WebRTC)             │
│              .part 断点续传 + 整包 SHA-256 校验                            │
│  store       SQLite(messages / ops / peers)                              │
│  identity    首启生成 EC P-256 自签证书 + 设备UUID,指纹=SHA-256(DER)     │
├──────────────────── 平台通道(app/,平台特定) ────────────────────────────┤
│  WebRTC      flutter_webrtc DataChannel ⇆ Envelope 流(LinkAuth 鉴权)     │
│  Hotspot     Android LocalOnlyHotspot / WifiNetworkSpecifier(Kotlin)      │
│  NFC         Android HCE NDEF 标签(HostApduService)+ nfc_manager 读取    │
└──────────────────────────────────────────────────────────────────────────┘
```

### 安全模型

| 层 | 机制 |
|---|---|
| 传输加密 | TLS(ECDHE + AES-GCM) ‖ WebRTC DTLS;均前向安全 |
| 服务端认证 | 证书指纹 pinning(SHA-256 of DER),非可信指纹直接拒连 |
| 客户端认证 | 配对签发的 32 字节共享令牌(gRPC 元数据 / WebRTC LinkAuth) |
| 配对防中间人 | 三选一:6 位 PIN(SAS)肉眼核对 / 一次性 tap 令牌(物理在场) / OOB 引导包令牌回显 |
| 未配对设备 | 仅能调用 `PairingService`,其余服务一律 unauthenticated |

### 一致性模型(双端数据一模一样)

- 消息以 `msg_id` 为全局主键,两端各自落同一份 SQLite;
- 本端变更(发消息/删消息)先落库并追加 `ops` 日志,在线即推,离线留表;
- 重连后双方交换游标(`Hello.applied_peer_seq`),补发对方缺失的 ops,幂等应用;
- 删除即墓碑:`ChatDeleted` 到达后两端都物理删除;对方离线时墓碑留 `ops` 表,重连补删;
- 解除配对:双端同时清空聊天记录与信任关系。

## 可选中转服务器(rendezvous)

NoServer 模式功能完整,但在跨互联网场景有两个物理约束:重启后远程链路
需要重新交换邀请、对方不在线时消息无法送达。可选的自建中转服务器
(几十 MB 单二进制)补齐这两块,**不影响任何现有功能**:

```
┌─ 设备A ─┐   ┌─ 设备B ─┐
│ gRPC/WebRTC P2P(优先,不经服务器) │
└────┬───┘   └────┬───┘
     │   rendezvous 服务器(可选)   │
     ├── presence:对方上线即时通知 → 自动 WebRTC 重连
     ├── signal:WebRTC 信令定向转发(密文)
     └── mailbox:对方离线时信封暂存,上线自取
```

**服务器是"瞎子"**:不持有任何私钥;经过它的载荷一律用配对令牌派生的
AES-256-GCM 应用层加密,服务器只见设备 ID 与密文。设备注册用身份证书
ECDSA 挑战签名防伪。

### 部署

```bash
# Release 下载对应平台二进制,或源码构建:
cd server && go build -o rendezvous .

./rendezvous -addr :47600 -db rendezvous.db
# 应用「设置 → 中转服务器」填: ws://服务器IP:47600/ws
# 有域名证书时放 Caddy/nginx 后面用 wss://域名/ws
```

## 目录

```
proto/littlelaw.proto      协议唯一事实源(改协议后运行 tool/gen_proto.ps1)
core/                      纯 Dart 引擎包(littlelaw_core),含端到端测试
app/                       Flutter 应用(Android/iOS/Windows/macOS/Linux)
server/                    可选中转服务器(Go,rendezvous)
tool/                      代码生成与安装包脚本
```

### iOS / macOS 未签名说明

macOS 版(.dmg/.zip)**未购买苹果开发者签名**,首次打开会提示"无法验证开发者":
右键点图标 →「打开」,或 系统设置 → 隐私与安全性 →「仍要打开」,或终端执行
`xattr -dr com.apple.quarantine /Applications/LittleLaw.app`。iOS 包同理需自签
(AltStore / Xcode)。要官方免警告安装需 Apple 开发者账号($99/年)做签名+公证。

## 构建与运行

### Windows / Linux / macOS(桌面端)

```powershell
cd app
flutter build windows --release   # 或 linux / macos
# 产物:app/build/windows/x64/runner/Release/littlelaw.exe
```

Windows 构建前置:开发者模式(符号链接);本仓库已处理
flutter_webrtc 的 libwebrtc 预编译包下载与 MSVC 兼容(/utf-8、协程告警静默)。

**同机双实例测试**(模拟两台设备):

```powershell
.\littlelaw.exe --data-dir C:\tmp\ll1 --name 测试机1
.\littlelaw.exe --data-dir C:\tmp\ll2 --name 测试机2   # 端口被占自动退化为动态端口
```

### Android

```powershell
cd app
flutter build apk --release --split-per-abi   # 单 ABI 包,体积小很多
```

已配置:全部局域网/热点/NFC/相机权限、组播锁、LocalOnlyHotspot、
HCE 服务、阿里云 Maven 镜像、老插件 compileSdk 修正(nfc-fix.gradle)。

### iOS

需要 macOS + Xcode。在 `ios/Runner.xcworkspace` → Signing & Capabilities 添加:
**Multicast Networking**、**Hotspot Configuration**、**NFC Tag Reading**
(entitlements 文件已备好)。iOS 无法程序化开热点/写 HCE,对应功能降级为
引导手动操作与读取方。

```powershell
cd app
flutter build ios --release
```

## 引擎测试

```powershell
cd core
dart test
# LAN e2e:发现→PIN配对→聊天→双端删除→离线补发→3MB文件→剪贴板→解绑
# OOB e2e:引导包配对→外部链路聊天/删除/2MB信封式文件/断链补发
# tap 配对:窗口内成功、令牌一次性重放拒绝、伪造令牌拒绝
```

## 协议常量

| 项 | 值 |
|---|---|
| gRPC TCP 端口 | 47520(被占自动退化动态端口,发现报文携带实际端口) |
| 发现 UDP 端口 | 47521 |
| 组播组 | 239.255.42.99 |
| 协议指纹 | magic `LLAW` + version `1` |
| 引导包前缀 | `LLB1.`(WebRTC offer/answer)/ `LLT1.`(局域网 tap) |

## 常见问题

- **发现不到设备**:同一 WiFi;Windows 防火墙放行(构建时已加规则);
  路由器 AP 隔离时走子网扫描兜底。
- **远程连接打洞失败**:运营商 CGNAT;在设置页配置自建 TURN 中继。
- **Flutter Windows 构建需开发者模式**:设置 → 开发者选项 → 开发者模式。
- **改协议**:`proto/littlelaw.proto` 改完跑 `powershell tool/gen_proto.ps1`。

