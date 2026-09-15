# 16 · 存储布局 —— 敏感明文泄漏进系统临时目录 + 数据不随程序目录

- **优先级**: P1（含 2 项敏感数据泄漏）
- **涉及文件**: `app/lib/main.dart:122`、`app/lib/backup.dart:74`、`app/lib/updater.dart:96`、`app/lib/chat_page.dart:229-231/255-269`、`tool/installer/littlelaw.iss:12/19`
- **置信度**: 高——全部逐行复核

## 现状盘点

| 内容 | 当前位置 | 评价 |
|------|----------|------|
| 数据主目录（db/身份/头像/inbox/vault） | `%APPDATA%`（Roaming）下，集中 | 集中✓，但位置有两个问题（F4/F5） |
| vault 解密缓存 | `<dataDir>/vault-cache` | ✓ 已在 dataDir |
| **备份恢复临时目录** | **`%TEMP%\ll_restore_*`** | ❌ 明文私钥+聊天记录进系统临时 |
| **语音录音** | **`%TEMP%\voice_*.m4a`** | ❌ 且从不删除 |
| **更新安装包** | **`%TEMP%\<assetName>`** | ❌ 共享目录 + 永不清理 |

## F1（P1·安全）备份恢复把解密后的私钥和聊天记录写进系统临时目录

`backup.dart:74`：`Directory.systemTemp.createTempSync('ll_restore_')`——`.llbk` 解密后的内容是**设备身份私钥 + 配对关系 + 全部聊天记录**，明文展开在 `%TEMP%` 下：
- 崩溃/断电跳过 `finally` 时**永久残留**，只有系统磁盘清理才会碰它；
- `%TEMP%` 同用户所有进程可读；网盘/企业终端管控常扫临时目录。

**修复**：恢复解包改到 `$dataDir/tmp/restore_<rand>/`（或直接内存中经 `archive` 处理不落盘），完成/失败即删；启动时清理残留的 `restore_*`。

## F2（P1·隐私）语音录音写进 %TEMP% 且从不删除

`chat_page.dart:229-231` 录音文件 `voice_<ts>.m4a` 写在系统临时目录；`_stopRecord`（255-269）**没有任何删除逻辑**——三条路径全部泄漏：
- 取消录音（send=false）：文件留下；
- 短于 0.6s 误触丢弃：文件留下；
- 已发送（消息走 inbox）：**原文件仍留在 %TEMP%**。

私密语音在系统临时目录无限累积。

**修复**：录音路径改 `$dataDir/tmp/voice_<ts>.m4a`；`_stopRecord` 的 finally 中：未发送（或已由引擎读取完）即删除。

## F3（P2·运维）更新安装包留在 %TEMP% 永不清理

`updater.dart:96` 下载到 `%TEMP%`（共享目录 TOCTOU 已在 11-P0-1 报告）；`install()` 只是 `Process.start` 后返回——**安装器 exe 永久残留**，多次更新累积上 GB。修复：下载到 `$dataDir/tmp/`，启动安装或失败后删除。

## F4（P1·设计）数据主目录放 Roaming（%APPDATA%），违反漫游配置文件规范

`main.dart:122`：`getApplicationSupportDirectory()` 在 Windows 上是 **Roaming** 目录。这里放的是 SQLite 数据库、身份私钥、vault 密钥、收件箱文件——按微软规范 Roaming 只应放**小体量设置**；域环境下 Windows 会尝试在登录/注销时同步整个目录：
- 登录变慢（同步几十 MB～GB 级文件）；
- 两台机器同时使用 → 同步冲突 → **SQLite 损坏**；
- 私钥随漫游配置在域内多机复制，扩大暴露面。

**修复**：改用 Local 状态目录（`%LOCALAPPDATA%`，path_provider 无直接 API 时用 `getPath(FOLDERID_LocalAppData)` 或 `getApplicationSupportDirectory` 的上级手工拼 LocalAppData）。

## F5（P1·设计，用户诉求）没有便携模式——数据不随程序目录

安装器配置 `littlelaw.iss:12/19`：`DefaultDirName={autopf}` + `PrivilegesRequired=lowest` → 默认装到**用户目录** `%LOCALAPPDATA%\Programs\LittleLaw`——该目录**用户可写**，便携化完全可行。

**建议方案（兼顾两种用户）**：
- 启动时检测：exe 旁存在 `portable.marker` 文件、或已存在 `<exeDir>/data` 目录 → dataDir = `<exeDir>/data`（便携模式，拷目录即迁移、卸载无残留）；
- 否则回退 LocalAppData（见 F4）——并处理"exe 目录不可写"（用户以管理员装进 Program Files）时静默回退；
- 引擎已有 `--data-dir` 参数（同机多实例测试在用），机制现成，只差默认值探测；
- 设置页加"打开数据目录"入口 + 显示当前模式（用户至少能找到数据在哪——目前没有任何 UI 暴露 dataDir 位置）。

## F6（P2）卸载/重装的数据孤儿

安装器的卸载流程不触碰 AppData 数据 → 重装用户以为"全新安装"却带着旧身份/旧会话，或反过来卸载后敏感数据永久残留在系统里无提示。便携模式（F5）天然解决；否则卸载时应询问"是否同时删除聊天数据"，并在设置页展示数据位置。

## 统一修复建议

新建 `$dataDir/tmp/` 作为**唯一**临时位置约定：

```
<dataDir>/            ← db / identity / avatars / inbox / vault / vault-cache
    tmp/              ← 全部临时文件：录音、更新包、备份解包
        （启动时清理 >48h 的残留；退出钩子清空）
```

三处 `%TEMP%` 使用（F1/F2/F3）全部改道；`Directory.systemTemp`/`getTemporaryDirectory` 在代码库中仅剩这 3 处，一次改完即可根绝。

## 验证方法

1. F1：恢复备份过程中用 Process Monitor 观察 `%TEMP%\ll_restore_*`；恢复后强制结束进程再查残留
2. F2：录音后取消 → 检查 `%TEMP%\voice_*.m4a` 仍在；发送语音后同样检查
3. F4：域环境（或模拟 Roaming 同步）观察登录时间与 db 同步冲突
4. F5：按方案实现后：exe 旁建 marker → 数据落在 exe 目录；删除 marker → 落 LocalAppData；Program Files 下不可写 → 自动回退不崩溃
