# 15 · 头像系统 —— 换头像后左侧菜单不更新（需重启）+ 无裁剪器

- **优先级**: P1
- **涉及文件**: `app/lib/avatar.dart`、`core/lib/littlelaw_core.dart`（`setMyAvatar`/`onProfileUpdate`）、`app/lib/main.dart`（设置流程）、`app/lib/adaptive_shell.dart`（左栏显示）
- **置信度**: 高——ImageCache 机制与事件链均已逐行复核

## 症状 1：Windows 上设置头像后，左侧菜单不更新，重启 App 才显示新头像

### 根因 F1（主凶）：`invalidate()` 只清存在性缓存，不清 Flutter ImageCache

`avatar.dart:13-38`：

```dart
static final Map<String, bool> _exists = {};
static void invalidate() => _exists.clear();          // ← 只清这个

static ImageProvider _provider(File f) =>
    ResizeImage.resizeIfNeeded(128, null, FileImage(f));   // ← 键 = ResizeImage(FileImage(path), 128)
```

头像文件**原地覆盖写**（`me.png` 路径不变，littlelaw_core.dart:516/521-526）。换头像后：
1. `invalidate()` 清掉 `_exists` → 下次 build 返回**新的** `ResizeImage(FileImage)` 实例；
2. 但 Flutter 全局 `ImageCache` 按 provider 相等性缓存解码结果——新旧实例 path/尺寸参数相同 → **同 key 缓存命中 → 永远返回旧解码图**；
3. 小图几乎不会被内存压力逐出 → **只能重启**。

全代码库无任何 `imageCache.evict` / `provider.evict()` 调用（已全局检索确认）。

**波及面不止自己**：对方换头像（`onProfileUpdate` → 写 `peer_<id>.png` 同路径覆盖 → `emitLocal(ProfileUpdated)` → 桌面壳 invalidate+重建，adaptive_shell.dart:45-46）、群头像（`groupAvatarPath` 同构）——**统统因 ImageCache 陈旧而看不到新图**，用户以为"对方没换头像"。

**修复**：`invalidate()` 改为同时逐出图像缓存——保存 provider 实例映射或按已知路径执行：

```dart
static void invalidate() {
  _exists.clear();
  for (final p in _evictPaths) {
    PaintingBinding.instance.imageCache
        .evict(ResizeImage.resizeIfNeeded(128, null, FileImage(File(p))));
  }
  _evictPaths.clear();
}
```

（注意陷阱：必须 evict **ResizeImage 包装后的键**，只 evict `FileImage` 无效——ResizeImage 才是进缓存的 provider。）更彻底的方案：头像文件名带版本号（`me_<mtime>.png`），路径即天然 cache key，`_exists` 与 ImageCache 同时自然失效。

### 根因 F2：自己设置头像不发本地事件，左栏根本不重建

`littlelaw_core.dart:521-526` `setMyAvatar` → 写文件 + `sync.broadcastProfile()`（推给对端）——**没有 `emitLocal(ProfileUpdated(myId))`**。

对照：收到**别人**的头像会 `emitLocal(ProfileUpdated(peerId))`（littlelaw_core.dart:219），桌面壳 45-46 行监听该事件 invalidate+重建。**唯独"我自己换了头像"这条路径没有任何事件** → 左栏（adaptive_shell.dart:177-188 的头像）连重建都不会发生。

所以用户看到的是 F1+F2 叠加：不重建（F2），重建了也是旧图（F1）。两个都要修。

**修复**：`setMyAvatar` 末尾 `sync.emitLocal(ProfileUpdated(identity.deviceId))`。

## 症状 2：设置头像没有选取框（裁剪）——设计缺口

`avatar.dart:71-78` `pickResized()`：选图 → `_encodeCapped` 按长边 256 **保比例**缩放——产出的是**非方形**图；显示时 `CircleAvatar` 做**中心裁剪**。脸不在照片正中的用户头像必然被切掉，且：

- 无裁剪框（不能选区域/缩放/拖动）
- 无预览确认（选完立即生效并同步给所有对端）
- 无恢复默认（头像一旦设置无法删掉回到图标兜底，引擎无 removeMyAvatar API）

**修复**：接入裁剪页（`image_cropper` 或自绘 `InteractiveViewer` + 圆形遮罩），正方形中心裁剪 → 编码；加"移除头像"入口（删文件 + 广播空头像，proto 的 `avatarPng` 空数组即"无头像"，协议已支持）。

## 伴随的设计不合理（F3-F6）

### F3（P2）ProfileUpdate 无版本号，每次建连重推头像

`sync_engine._registerSink`：每次会话建立即互推 profile → 对端 `onProfileUpdate` **无条件重写头像文件**（内容相同也重写）——文件 mtime 持续抖动；将来若有基于 mtime 的缓存/同步逻辑必被误触发。修复：ProfileUpdate 加 content hash（或比较字节），未变化不落盘。

### F4（P2）选图无 loading 态、无防重入

`main.dart:1258` avatar onTap：`pickResized` 内 `_encodeCapped` 对大图 256→192→144… 逐级重编码 PNG，可达数秒——期间无任何 busy 提示，可再次点击重复触发。修复：busy 标志 + 转圈。

### F5（交叉引用）96KB 上限静默拒发

`setMyAvatar` 不校验大小，超限头像经 `profileProvider` **静默只发名字**（littlelaw_core.dart:200 附近，详见 06-P2-16）——对端永远收不到且双方均无提示。`pickResized` 的 cap 逻辑 + 启动时 `ensureMyAvatarSendable` 兜底说明这是已知坑，但"静默"仍未解决。

### F6（交叉引用）大图全量解码 OOM 风险

`_encodeCapped`/探测尺寸用 `instantiateImageCodec(raw)` 全量解码，50MP 照片 ~200MB RGBA（详见 11-P2-10）。

## 验证方法

1. F1：Windows 换头像 → 设置页立即变（ProfilePage 自己 setState 了）→ 左栏/会话列表仍是旧图 → 重启后左栏才变。修 F1 后：无需重启全端立即更新
2. F2：仅修 F2 不修 F1 → 左栏重建但仍是旧图（用于区分两个成因的验证）
3. F1 波及面：对端换头像 → 本端所有位置不更新直到重启
4. 症状 2：选一张人脸偏左的照片设为头像 → 圆形裁剪后人脸被切
