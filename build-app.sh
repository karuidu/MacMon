#!/bin/bash
# 把 Swift Package 的 release 产物组装成可双击运行的 MacMon.app
set -euo pipefail

cd "$(dirname "$0")"

APP="MacMon.app"
BUILD_DIR=".build/release"
BIN="MacMon"
VERSION="1.0.0"
BUNDLE_ID="com.macmon.desktop"

echo "▸ 构建 release…"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
# 受限环境（CI、外层已经套了 sandbox 的容器）里 SwiftPM 编译 manifest 时会再套一层
# sandbox-exec，可能直接报 `sandbox_apply: Operation not permitted` 并伪装成
# `Invalid manifest`。这种环境用 SWIFT_BUILD_ARGS=--disable-sandbox ./build-app.sh 绕过。
swift build -c release ${SWIFT_BUILD_ARGS:-}

if [ ! -x "$BUILD_DIR/$BIN" ]; then
  echo "✗ 未找到产物 $BUILD_DIR/$BIN"
  exit 1
fi

echo "▸ 组装 ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$BIN" "$APP/Contents/MacOS/$BIN"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${BIN}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacMon</string>
    <key>CFBundleDisplayName</key>
    <string>MacMon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MacMon · 本地系统健康监控</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# 图标：优先用 assets/AppIcon.icns（每个尺寸单独渲染过，见 assets/build-icon.sh）；
# 没有就退回「拿 icon-1024.png 缩放打包」的老路
ICON_DST="$APP/Contents/Resources/AppIcon.icns"
PRESET=""
for candidate in "assets/AppIcon.icns" "AppIcon.icns"; do
  [ -f "$candidate" ] && PRESET="$candidate" && break
done

if [ -n "$PRESET" ]; then
  cp "$PRESET" "$ICON_DST"
elif [ -f "assets/icon-1024.png" ] && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$(mktemp -d)/MacMon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512; do
    sips -z $size $size "assets/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    sips -z $((size*2)) $((size*2)) "assets/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$ICON_DST" 2>/dev/null || true
fi

if [ -f "$ICON_DST" ]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
  echo "▸ 图标：$(basename "$ICON_DST") $(du -h "$ICON_DST" | cut -f1)"
else
  echo "▸ 图标：未找到，使用系统占位图"
fi

echo "▸ ad-hoc 签名…"
codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/    /' || {
  echo "⚠️ 签名失败，但 .app 仍可本地运行"
}

echo "▸ 校验…"
codesign -dv "$APP" 2>&1 | head -4 | sed 's/^/    /'

SIZE=$(du -sh "$APP" | cut -f1)
echo ""
echo "✓ 完成：$(pwd)/$APP  ($SIZE)"
echo "  双击运行，或执行： open $APP"
echo "  诊断模式：       ./$APP/Contents/MacOS/MacMon --diagnose"
