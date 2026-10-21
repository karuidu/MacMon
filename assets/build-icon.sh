#!/bin/bash
# 生成 macOS 应用图标：assets/AppIcon.icns + assets/icon-1024.png
#
# 每个尺寸都**单独渲染**，而不是把 1024 缩下去——16/32px 用简化路径
# （见 make-icon.swift 里的 simplified），小尺寸才不会糊。
set -euo pipefail
cd "$(dirname "$0")"

tmp="$(mktemp -d)"
set_dir="$tmp/MacMon.iconset"
mkdir -p "$set_dir"

render() { swift make-icon.swift pulse "$1" "$2" >/dev/null; }

render "$set_dir/icon_16x16.png" 16
render "$set_dir/icon_16x16@2x.png" 32
render "$set_dir/icon_32x32.png" 32
render "$set_dir/icon_32x32@2x.png" 64
render "$set_dir/icon_128x128.png" 128
render "$set_dir/icon_128x128@2x.png" 256
render "$set_dir/icon_256x256.png" 256
render "$set_dir/icon_256x256@2x.png" 512
render "$set_dir/icon_512x512.png" 512
render "$set_dir/icon_512x512@2x.png" 1024

render "icon-1024.png" 1024

iconutil -c icns "$set_dir" -o AppIcon.icns
rm -rf "$tmp"

echo "✓ assets/AppIcon.icns  $(du -h AppIcon.icns | cut -f1)"
echo "✓ assets/icon-1024.png $(du -h icon-1024.png | cut -f1)"
