# 11 · 外围功能 —— 更新器无完整性校验与备份 Zip Slip（2 个 P0）

- **优先级**: P0（安全）
- **涉及文件**: `app/lib/updater.dart`、`app/lib/backup.dart`、`app/lib/call.dart`、`app/lib/call_page.dart`、`app/lib/hotspot*.dart`、`app/lib/push_wake.dart`、`app/lib/share_*.dart`、`app/lib/nfc_pair.dart`、`app/lib/blob_widgets.dart`、`app/lib/media_viewers.dart`、`app/lib/avatar.dart`
- **置信度**: 高，两个 P0 已逐行复核源码

## P0

### P0-1 更新包下载后无任何哈希/签名校验即执行

`updater.dart:94-133`（已复核）：下载后直接 `Process.start(path, ...)`（Windows）/`installApk`（Android）。

- GitHub API 响应里**自带 `assets[].digest`（sha256）但代码完全没用**；无签名/哈希清单
- `u.url` 不校验 scheme/host（无纵深防御）
- 文件写在共享临时目录后延迟执行，存在本地 TOCTOU 窗口

一旦 GitHub 账号被盗/Release 被替换/下载源被劫持（整条链唯一防线是到 GitHub 的 TLS），恶意安装包被静默下载并以用户权限执行（RCE）。

**修复**：1) 解析 digest，下载后校验 sha256，不匹配删除拒装；2) 校验 URL 必须 https 且 host ∈ {github.com, objects.githubusercontent.com, release-assets.githubusercontent.com}；3) 更强方案：Release 附 minisign/cosign 签名，安装前验签。

### P0-2 恢复流程 Zip Slip 任意文件写入

`backup.dart:76-80`（已复核）：

```dart
for (final file in archive.files) {
  if (!file.isFile) continue;
  final out = File('${tmp.path}/${file.name}');   // ← file.name 完全未净化
  await out.writeAsBytes(file.content as List<int>);
}
```

备份文件本身无来源认证（口令由提供者告知）。攻击者自制 `.llbk` 让用户"帮忙恢复"，条目名 `..\..\Startup\x.exe` 即可写到临时目录外任意位置——**用户权限下的任意文件写**（持久化/RCE），Android 上同理可覆盖应用私有目录。

**修复**：解包前对每个条目校验拒绝绝对路径/盘符，`p.normalize` 后 `p.isWithin(tmp.path, target)` 断言；或白名单只解 `_backupFiles` 中的固定 4 个文件名。

## P1（6 项）

### P1-3 FilePicker.saveFile 返回值按旧版 String 处理——备份保存在 Windows/Android 上报错

`backup.dart:48-57`：file_picker 12.x 的 `saveFile` 返回 `Uri?` 且**平台已自动写盘**。`result.toString()` 得 `file:///C:/...` → `existsSync()` 对非法路径返回 false → 走"手动落盘"分支 → Windows `FileSystemException`/Android content URI 必败。**文件其实已保存成功，UI 却弹"备份失败"**。修复：用 `result.toFilePath()` 且不再手动写；Android 仅展示 URI。

### P1-4 恢复非原子：先 dispose 引擎再逐文件覆盖，失败后应用处于残废状态

`backup.dart:81-88`：copy 中途失败（磁盘满/占用）时引擎已 disposed 但应用不退出——继续运行在已销毁的引擎上；数据目录处于"新 db + 旧 identity"混合状态。修复：staging 目录 + rename 交换；dispose 移到文件全部落位后；失败提示重启。

### P1-5 通话早到 ICE candidate 被静默丢弃（无缓冲）

`call.dart:213-219`：被叫响铃期间 `_pc == null`，主叫 candidate 到达即 `return` 永久丢弃（主叫 host 候选几秒内收完，晚接电话≈候选全丢）；反向 addCandidate 在 setRemoteDescription 前调用直接抛错。对称 NAT 下打洞失败。修复：pending 队列 + SRD 后 flush。

### P1-6 信令事件处理中的异步异常未捕获

`call.dart:201-219`：`_onAnswer/_onCandidate` 未 await 未 catch——SDP 非法/answer 重复投递抛"wrong state"成未处理 zone 异常，状态机卡在 connecting 只能等 45s 超时。修复：整体 try/catch 走 teardown；answer/offer 防重放。

### P1-7 startCall/accept 无重入保护

`call.dart:77-107`：状态在多个秒级 await 之后才改变。来电界面双击接听：创建第二个 PC 覆盖 `_pc`（**第一个 PC 与摄像头/麦克风轨道永不释放**）、向对端连发两个 answer。修复：入口同步改状态或 `_busy` 互斥。

### P1-8 hotspot 页 await 之后无条件 setState

`hotspot_page.dart:36-76/128-131`：权限对话框（耗时且用户可退出页面）之后 `setState` 无 mounted 检查 → `setState() called after dispose()` 崩溃；关闭热点按钮无 try/catch。修复：每处 await 后判 mounted；包异常。

## P2（11 项）

| # | 位置 | 问题 | 修复 |
|---|------|------|------|
| 1 | updater.dart:88-90 | 检查失败（断网/GitHub 限流）与"无更新"同返回 null——UI 弹"已是最新"，用户可能长期停留在有漏洞的版本 | 三态结果，失败明示 |
| 2 | updater.dart:100-125 | 下载失败路径 HttpClient 泄漏；全流程无总超时——下载挂起则进度弹窗永远不消失 | future.timeout；catch 中 close(force) |
| 3 | push_wake.dart:39-48 | 仅前台 onMessage 唤醒，未注册 background handler（iOS 被杀进程不拉起）——离线唤醒形同虚设；rendezvous 监听绑死旧实例 | 注册顶层 background handler；实例变更重订阅 |
| 4 | share_handler.dart:23-38 | 冷启动分享与引擎就绪竞态：peers 未加载完时 initial share 被静默丢弃且提示错误 | 缓存 payload 待就绪后 dispatch |
| 5 | nfc_pair.dart:31-36 | 配对窗口 Timer 不可取消——重开窗口后旧 Timer 到期把**新**载荷清掉，第二窗口静默失效 | Timer 存字段，重开先 cancel |
| 6 | hotspot.dart:13 | WiFi 二维码未转义 `; \ , : "`——SSID/密码含特殊字符时扫码解析错误 | 按 WIFI QR 规范转义 |
| 7 | blob_widgets.dart:242/247 | 扫码回调 pop 未检查 mounted（相机异步停止窗口） | 回调入口判 mounted |
| 8 | blob_widgets.dart:44 | 单码容量判定用 UTF-16 length 而非字节数——非 ASCII 载荷永远进不了单码模式 | `utf8.encode().length` |
| 9 | media_viewers.dart:94-100 | 视频失败经 `player.stream.error` 上报而非 open() 抛异常——损坏文件永久黑屏；setState 无 mounted 保护 | 订阅 error 流 |
| 10 | avatar.dart:45-47 | 探测尺寸时全尺寸解码，50MP 照片 ~200MB RGBA，低端手机 OOM | ImageDescriptor 仅取尺寸 |
| 11 | share_out.dart:32/114 | Android shareFile/openFile 的 PlatformException 未捕获，直接冒到聊天页按钮 | try/catch + 降级提示 |

## 验证建议

- P0-1：修改 hosts 把 github.com 指向测试机，架一个返回任意 exe 的假 Release API，观察下载后是否直接执行
- P0-2：构造含 `..\x.txt` 条目的 zip 打包为 .llbk，恢复后检查临时目录外是否出现 x.txt
- P1-3：Windows 上点"创建备份"选保存位置——文件已生成但弹"备份失败"
- P1-5/7：主叫发起通话、被叫响铃 5 秒后接听（或双击接听键），观察连接成功率和资源占用
