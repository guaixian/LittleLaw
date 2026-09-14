import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme/app_theme.dart';

/// 首次使用引导:4 页滑切,看完即不再出现(设置页可重看)。
class IntroPage extends StatefulWidget {
  const IntroPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      Icons.lock_outline,
      '端到端加密',
      '没有中心服务器。消息、文件只在你的设备之间直达并加密存放,'
          '第三方(包括中转服务器)只能看到密文。',
    ),
    (
      Icons.hub_outlined,
      '四种连接',
      '同一网络自动发现;碰一碰/扫一扫免 PIN;没有路由器用热点;'
          '跨互联网走 WebRTC 打洞,可自建中继补齐离线送达。',
    ),
    (
      Icons.forum_outlined,
      '聊天与群',
      '文字、语音、图片、视频、文件、剪贴板、表情回应、已读回执、'
          '消息搜索;建群拉群一样不落。',
    ),
    (
      Icons.folder_outlined,
      '文件自动归档',
      '收到的内容按设备/群自动分目录(图片/视频/语音/文件),'
          '磁盘上以密文存放,查看时自动解密。',
    ),
  ];

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skin = themeController.skin;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: Text(L10n.t('intro.skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
                  final (icon, title, body) = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 36, vertical: 8),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              (MediaQuery.sizeOf(ctx).height -
                                      MediaQuery.paddingOf(ctx).vertical -
                                      180)
                                  .clamp(0.0, 560.0)
                                  .toDouble(),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                gradient: skin.gradient,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        skin.primary.withValues(alpha: 0.35),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child:
                                  Icon(icon, color: Colors.white, size: 44),
                            ),
                            const SizedBox(height: 28),
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 14),
                            Text(body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.6,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? skin.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _next,
                  child: Text(_page == _pages.length - 1
                      ? L10n.t('intro.start')
                      : L10n.t('intro.next')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
