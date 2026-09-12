#!/usr/bin/env bash
# LittleLaw Linux .deb 打包(ubuntu runner 内运行)
# 用法: bash tool/installer/make_deb.sh <version> <bundle_dir> <output_dir>
set -e

VERSION="${1:-1.0.0}"
BUNDLE="${2:-app/build/linux/x64/release/bundle}"
OUT="${3:-app/build/linux-deb}"
PKG="build/deb-stage/littlelaw_${VERSION}_amd64"

rm -rf "$PKG"
mkdir -p "$PKG/usr/lib/littlelaw" \
         "$PKG/usr/share/applications" \
         "$PKG/usr/share/icons/hicolor/256x256/apps" \
         "$PKG/DEBIAN"

cp -r "$BUNDLE"/* "$PKG/usr/lib/littlelaw/"
chmod +x "$PKG/usr/lib/littlelaw/littlelaw" || true

cat > "$PKG/DEBIAN/control" <<EOF
Package: littlelaw
Version: ${VERSION}
Section: net
Priority: optional
Architecture: amd64
Maintainer: guaixian
Depends: libgtk-3-0, libmpv1 | libmpv2
Description: LittleLaw - NoServer 局域网端到端加密多端通讯
 聊天、剪贴板、文件传输,WebRTC 跨网互联,全程端到端加密。
EOF

cat > "$PKG/usr/share/applications/littlelaw.desktop" <<EOF
[Desktop Entry]
Name=LittleLaw
Comment=NoServer LAN E2E messenger
Exec=/usr/lib/littlelaw/littlelaw
Icon=littlelaw
Type=Application
Categories=Network;Utility;
Terminal=false
EOF

# 图标(存在则带上)
ICON="app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
[ -f "$ICON" ] && cp "$ICON" "$PKG/usr/share/icons/hicolor/256x256/apps/littlelaw.png"

mkdir -p "$OUT"
dpkg-deb --build "$PKG" "$OUT/littlelaw-linux-amd64.deb"
echo "built: $OUT/littlelaw-linux-amd64.deb"
