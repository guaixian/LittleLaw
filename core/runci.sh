#!/bin/bash
set -e
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y -qq libsqlite3-0 >/dev/null 2>&1 || true
dart pub get >/dev/null 2>&1
for i in 1 2 3; do
  echo "=== RUN $i ==="
  dart test test/multidevice_test.dart --concurrency=1 2>&1 | grep -E "All tests|Some tests|failed" | head -3 || true
done
echo "=== FULL SUITE ==="
dart test --concurrency=1 2>&1 | grep -E "All tests|Some tests|failed" | head -3 || true
