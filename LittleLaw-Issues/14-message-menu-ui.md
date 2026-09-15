# 14 · 消息功能菜单 —— 桌面右键交互反直觉与图标风格混乱

- **优先级**: P1
- **涉及文件**: `app/lib/chat_page.dart`（`_showMessageMenu`/`_messageSheet`/`_inlineToolbar`/`_barBtn`/`_sheetAction`）
- **置信度**: 高——全部逐行复核；视觉判断部分附截图指引供开发者确认

## 症状

消息的长按/右键功能菜单"显示得奇怪"，部分图标"看起来不协调"。

## F1（P1）桌面右键菜单是"流内嵌工具栏"——把消息往下推、不跟随光标、要横向滚动

`chat_page.dart:1160-1168` + `_inlineToolbar`（685-798）：

```dart
// 桌面内联工具栏作为常规布局子项放在消息上方(占位,可正常点击)
if (_menuMsgId == m.msgId) {
  children.add(ConstrainedBox(..., child: _inlineToolbar(m)));
}
children.add(bubble);
```

三个反直觉点：
1. **右键（`onSecondaryTapDown`，1445 行）触发的不是跟随鼠标的上下文菜单**，而是把一条工具栏插进消息流、把目标消息和下方所有内容**往下推**——与 Windows/macOS 用户预期完全相反；
2. 第二排功能按钮放在 `SingleChildScrollView(horizontal)`（719 行）里——**"删除"等按钮需要横向滚动才能看到**，菜单里还要滚动是极差的可用性；
3. 工具栏 `CrossAxisAlignment.start`（703 行）**固定靠左**——对方消息（左侧气泡）和我方消息（右侧气泡）的菜单位置不跟随气泡对齐，视觉错位。

**修复**：桌面右键改用标准上下文菜单——`showMenu(position: 右键坐标)`（Material 3 Menu + 快捷表情行），或 Popover 定位到气泡旁；内联工具栏只保留给触屏长按（如果有的话），并去掉横向滚动（自动换行成两排图标）。

## F2（P1）移动端文本消息没有"分享"入口，桌面却有——死代码暴露的不一致

`chat_page.dart:612-623`（移动端 sheet）：

```dart
if (Message.hasFilePayload(m.kind) && m.fileState == done)   // ← 只放行文件消息
  _sheetAction(sctx, Icons.ios_share, '分享', () async {
    ...
    if (m.kind == Message.kindText) {        // ← 恒为 false：死代码
      ShareOut.shareText(m.text);
```

外层条件要求文件消息，内层的文本分支永远走不到——**移动端文本消息无法分享到微信/QQ 等应用**。而桌面内联条的分享按钮外层条件（753-755 行）包含 `kindText`，桌面上文本**可以**分享。README 宣称"分享到其他应用——长按消息"对所有消息可用，两端行为不一致。

**修复**：移动端分享按钮条件改为与桌面一致（kindText || 文件已下载），删除死分支。

## F3（P2）图标风格/家族/尺寸三重混乱——"不协调"的直接来源

| 功能 | 移动端 sheet | 桌面内联条 | 问题 |
|------|--------------|------------|------|
| 复制 | `Icons.copy_outlined` 22px（569） | `Icons.copy`（filled）15px（724） | outlined vs filled 两种家族 |
| 分享 | `Icons.ios_share`（614/767） | 同左 | **iOS 专属图标出现在 Windows/Android** |
| 转发 | `Icons.shortcut`（584/756） | 同左 | Android 12 风格箭头，桌面观感突兀 |
| 打开方式 | `Icons.open_with`（628） | 同左（738） | 四向箭头与相邻 open_in_new 语义易混 |
| 多选 | `Icons.checklist`（598/777） | 同左 | Google Apps 风格 checklist |
| 表情 | emoji 26px | emoji 17px | 与 Material 图标并置，尺寸比随端漂移 |

README 声明设计系统"Material 线性图标(无 emoji)"——实际菜单里混着 iOS 系统图标、Android 12 图标、filled/outlined 两种家族、emoji，正是用户"有的 icon 看起来太不维和"的原因。

**修复**：统一为单一家族（建议 Material Symbols **outlined** 全套：复制 `content_copy`、转发 `forward`/`shortcut` 保留、分享 `share`、打开方式 `open_in`、多选 `checklist`、删除 `delete_outline`）；表情行保留 emoji 但加统一容器底色与 Material 行视觉分隔。

## F4（P2）桌面内联条按钮无 Tooltip——15px 裸图标不可辨识

`_barBtn`（801-808）：`InkWell` 直接包裹 15px 图标，**没有 Tooltip**。配合 F1 的横向滚动，不看悬停提示（实际也没有悬停提示）根本不知道每个按钮是什么。修复：`_barBtn` 内包 `Tooltip(message: label)`；图标尺寸提到 18-20px。

## F5（P2）按钮位置随消息类型漂移

移动端 sheet 用 `Expanded` 均分 + `growable` 标记（596-649）："多选"固定在第二排末尾、"删除"在第三排末尾，但每排按钮数量随消息类型（文本 4 个、文件 5-7 个）变化——**同一功能在不同消息上位置不同**，肌肉记忆无效。修复：固定栅格（每行 4 个，不足留空）或改列表式菜单（图标+文字左对齐，参照微信/Telegram）。

## F6（P2）菜单交互细节

- 内联条插在消息上方（流内），若目标消息在视口顶部，**菜单渲染在视口外**，无自动滚动；
- 桌面按 **ESC 不关闭**菜单（只有点击空白关闭，825 行）；
- 打开菜单期间点击另一条消息 = 切换到新菜单（526 行 toggle），而非先关闭——连续误触体验差。

## 修复优先级建议

1. F1：桌面改 `showMenu(position:)` 标准上下文菜单（一次改动解决三四个可用性问题）
2. F2：补移动端文本分享入口（删死代码，两行改动）
3. F3+F4：统一图标家族 + 全部加 Tooltip
4. F5/F6：栅格化与交互细节

## 验证方法

1. F1：Windows 桌面右键任意消息——观察消息被下推、菜单靠左、窄窗口下第二排出现横向滚动条
2. F2：移动端长按文本消息——操作面板无"分享"；桌面右键同一条消息——有分享且可用
3. F3：对照上表逐个截图，两个平台并排比较图标家族
