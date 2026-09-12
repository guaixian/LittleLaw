/// 显式丢弃 Future(替代 pedantic 的 unawaited,避免额外依赖)。
void unawaited(Future<void> future) {}
