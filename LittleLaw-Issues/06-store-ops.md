# 06 · 存储层与引擎门面 —— 数据丢失与群功能瘫痪级缺陷

- **优先级**: P0（含 2 项数据丢失/功能瘫痪级）
- **涉及文件**: `core/lib/src/store/store.dart`、`core/lib/littlelaw_core.dart`
- **置信度**: 高，全部关键结论已逐行复核源码
- **审查方式**: 静态深度审读，交叉验证了 sync_engine/pairing/identity 的调用路径

## P0

### P0-1 deleteGroup 按 peer_id 清空全部 ops —— 解散群即误删 1:1 未确认消息

`store.dart:722-735`：

```dart
void deleteGroup(String groupId, {bool keepMessages = false}) {
  ...
  for (final m in members) {
    _db.execute('DELETE FROM ops WHERE peer_id=?', [m]);
  }
}
```

ops 表按**成员 deviceId** 入账，不区分 1:1 与群。解散群/被移出时会把发给该成员的**所有**未 ACK ops 一并删除——包括 1:1 离线排队消息、回执、表情 op。触发面：本端 `dissolveGroup`（littlelaw_core.dart:659-665）、接收端收到解散/被移出通知（sync_engine.dart:516、525）。

**示例**：A 收到群解散通知 → A 发给 B/C/D 的全部待发 1:1 消息被摧毁。

**附带 bug**：dissolve 流程先 broadcast 后删 ops，**刚追加的解散 op 也被自己删掉** → 离线成员永远收不到解散通知，幽灵群残留。

**修复**：不按 peer_id 删 ops；群 op 增加会话维度标识，靠 ACK 压缩 + 墓碑 TTL 回收。

### P0-2 appendOp 对不存在的 peer 行执行 `.first` 抛 StateError —— 群功能永久瘫痪

`store.dart:628-634`：

```dart
_db.execute('UPDATE peers SET next_op_seq = next_op_seq + 1 WHERE device_id=?', [peerId]);
final seq = (_db.select(
        'SELECT next_op_seq AS n FROM peers WHERE device_id=?', [peerId])
    .first['n']) as int;    // ← peer 不存在时 StateError
```

peer 行不存在时 UPDATE 影响 0 行（不报错），随后 `.first` 对空结果抛 `StateError('No element')`。而 unpair 的 `_wipePeer`（pairing.dart:193-198）只删 peers/ops/会话，**不清理 group_members**；`groupRecipients`（store.dart:738-742）不过滤 peers 表。

**结果**：解配某个群成员后，向该群发消息、发已读回执、踢人/退群（`broadcastGroupSync` 的 extraTargets 含被移除者）都会命中已删成员 → 抛异常，**该群所有写操作永久失败**。

**修复**：appendOp 前校验 peer 存在；unpair 时同步清理 group_members。

## P1

### P1-3 opsSince 墓碑 TTL 跳过破坏连续游标协议 → ACK 永久卡死 + 重放风暴

`store.dart:654-657`：删除类 op 超过 `deleteOpTtlMs` 后重放时被 `continue` 跳过。但接收端游标是**前缀连续推进**（`_advanceCursor` 的 `while set.contains(prefix+1)`），跳过 seq=k 后游标永久停在 k-1：后续消息仍被应用但 SyncAck 永不前进 → 对端 ops 永不压缩、每次重连全量重放、在线时反复回 Hello 形成循环。触发条件极普通：**对方离线超 48 小时期间我删过消息**。修复：过期墓碑改为可推进游标的空操作。

### P1-4 appendOp 三条语句无事务、pseq 无 UNIQUE 约束

`store.dart:629-638`：UPDATE→SELECT→INSERT 之间崩溃会"烧掉"序号 → 永久空洞（后果同 P1-3）；`ops` 表仅普通索引，并发可产生重复 pseq。修复：事务包裹 + `UNIQUE(peer_id, pseq)`。

### P1-5 nextLamport 取 MAX —— 删除最高位消息后时钟回退、清空会话后归零

`store.dart:484-489`：`MAX(lamport)+1`。删除会话内 lamport 最大的消息后新消息复用旧值；`clearConversation` 直接归零——48h+ 离线对端的新消息 lamport 1..N 排在旧消息之下，**聊天记录次序错乱**、分页边界跳消息。修复：per-conv 持久化水位，删除不回退。

### P1-6 conversationSummaries 在 lamport 并列时返回重复会话条目

`store.dart:600-603`：两端并发发送合法产生相同 lamport 时，子查询命中 N 行 → 最近会话列表出现重复条目。正常并发即可触发。修复：外层按 conv_id 取单行。

### P1-7 PairingManager 携带的是请求端口而非实际绑定端口

`littlelaw_core.dart:139-143`：47520 被占退化为随机端口时，配对广播的 `myInfo.port` 仍指 47520 → 对端存错端口 → unpair 通知/answer 回送达错端口。修复：端口注入挪到 serveEngine 成功后，传 boundPort。

## P2（11 项）

| # | 位置 | 问题 | 修复 |
|---|------|------|------|
| 8 | store.dart:287-309 | 迁移回填无事务、catch-all 吞错，崩溃后 pseq=0 的 op 永不重放（丢数据） | 事务包裹；按 schema 查列存在性 |
| 9 | store.dart:678-684 | insertGroup 三步写无事务，崩溃窗口群存在但成员为空 → 群消息静默不扇出 | 包 BEGIN/COMMIT |
| 10 | store.dart:326-332 | upsertPeer 冲突分支重置 is_self——"我的设备"标记被重新配对清零 | 冲突时不更新 is_self |
| 11 | store.dart:457/535 | IN 列表无上限，批量删除/置读超 999 参数抛 SqliteException | 分批 500 |
| 12 | store.dart:744-747 | `_dbSelfId` late 字段，Store 独立使用即崩 | open() 必填或默认值 |
| 13 | littlelaw_core.dart:300-304 | server.shutdown 超时被吞后仍关 store，in-flight RPC 访问已关库 | 超时先断活跃 call 再关库 |
| 14 | littlelaw_core.dart:131-192 | start() 异常路径资源泄漏（库句柄/半初始化 server） | try/catch 统一 dispose |
| 15 | littlelaw_core.dart:653-655 | leaveGroup：本端保留历史，我的镜像设备却走"被移出"路径全删——违反镜像承诺 | 镜像设备加标记或过滤 |
| 16 | littlelaw_core.dart:521-526 | setMyAvatar 不校验 96KB，超限头像静默永不同步 | 写入前校验并提示 |
| 17 | littlelaw_core.dart:268-271 | 发现报文**空指纹**绕过配对指纹校验（`isNotEmpty` 前置条件） | 空指纹同样丢弃 |
| 18 | littlelaw_core.dart:293 / upnp.dart:17 | UPnP 静态映射状态跨实例共享，双实例互删映射 | 实例化或引用计数 |

## 验证建议

- P0-1：A、B、C 建群 → A 给 B 发一条 1:1 消息（B 离线）→ A 解散群 → 检查 A 的 ops 表：发给 B 的 1:1 消息已消失，B 上线后收不到
- P0-2：A、B、C 建群 → A 解配 C → A 在群里发任何消息/回执 → 观察 StateError，群从此不可用
- P1-3：A 删除若干消息 → B 离线 49 小时 → B 上线 → 观察 B 的 SyncAck 游标是否卡在删除 op 之前、重连是否全量重放
