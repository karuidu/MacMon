#!/bin/bash
# 打可以直接挂到 GitHub Release 的分发包，默认一次出三种架构。
#
# 为什么不能把 MacMon.app 直接上传：
#   1. `.app` 是**目录**，Release 资产只收文件，必须先压成一个文件
#   2. 打包用 `ditto`，不用 `zip -r`：后者会跟随符号链接、丢扩展属性和资源分叉。
#      这个 bundle 目前只有 5 个普通文件，实测 `zip -r` 也过得了签名校验；但一旦以后加了
#      framework（内部全是符号链接），`zip -r` 打出来的包就会签名失效。从一开始就用对的。
#   3. 只出单架构的话，另一种芯片的 Mac 打开会报「无法打开」。
#
# 架构怎么来的：**只编译一次 universal，再用 `lipo -thin` 切出单架构**。
# 好处是三份包的代码完全同源（同一份 fat 二进制切片），不用编三遍。
# 注意 `lipo -thin` 会让原签名失效，所以每个包都要重新 ad-hoc 签名 ——
# 这一步由 build-app.sh 里的 `codesign --force --deep --sign -` 完成，回验阶段会复查。
#
# 用法：
#   ./scripts/make-release.sh                     # 1.0.0，universal + arm64 + x86_64
#   VERSION=1.1.0 ./scripts/make-release.sh       # 指定版本
#   TARGETS=universal ./scripts/make-release.sh   # 只出 universal（一个包通吃）
#   TARGETS=split ./scripts/make-release.sh       # 只出两个单架构包
#
# 产物落在 dist/：
#   MacMon-<版本>-universal.zip / -arm64.zip / -x86_64.zip
#   SHA256SUMS            三个包的校验和
#   release-notes.md      可直接喂给 gh release create --notes-file
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
TARGETS="${TARGETS:-all}"
SCRATCH=".build/universal"
OUT="dist"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"

case "$TARGETS" in
  all)       VARIANTS=(universal arm64 x86_64) ;;
  split)     VARIANTS=(arm64 x86_64) ;;
  universal) VARIANTS=(universal) ;;
  *) echo "✗ TARGETS 只能是 all / split / universal，收到：$TARGETS"; exit 1 ;;
esac

echo "▸ 编译 universal（arm64 + x86_64）…"
swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" ${SWIFT_BUILD_ARGS:-}
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" \
  ${SWIFT_BUILD_ARGS:-} --show-bin-path)"
FAT_BIN="$BIN_DIR/MacMon"
[ -x "$FAT_BIN" ] || { echo "✗ 没找到产物 $FAT_BIN"; exit 1; }
echo "  产物：$FAT_BIN"
echo "  架构：$(lipo -archs "$FAT_BIN")"

mkdir -p "$OUT"
rm -rf "$OUT/work" "$OUT/pkg"
rm -f "$OUT"/MacMon-"$VERSION"-*.zip "$OUT/SHA256SUMS"

for variant in "${VARIANTS[@]}"; do
  echo ""
  echo "=== $variant ==="

  if [ "$variant" = "universal" ]; then
    SRC_DIR="$BIN_DIR"
    EXPECTED_ARCHS="x86_64 arm64"
  else
    # 从 fat 二进制切出单架构。切完签名失效，交给 build-app.sh 重签。
    SRC_DIR="$OUT/work/$variant"
    mkdir -p "$SRC_DIR"
    lipo "$FAT_BIN" -thin "$variant" -output "$SRC_DIR/MacMon"
    chmod +x "$SRC_DIR/MacMon"
    EXPECTED_ARCHS="$variant"
  fi

  PKG_ROOT="$OUT/pkg/$variant"
  SKIP_BUILD=1 BIN_DIR="$SRC_DIR" APP_PATH="$PKG_ROOT/MacMon.app" VERSION="$VERSION" ./build-app.sh

  APP="$PKG_ROOT/MacMon.app"
  actual="$(lipo -archs "$APP/Contents/MacOS/MacMon")"
  [ "$actual" = "$EXPECTED_ARCHS" ] || {
    echo "✗ 架构不对：期望 $EXPECTED_ARCHS，实际 $actual"; exit 1; }

  ZIP="$OUT/MacMon-${VERSION}-${variant}.zip"
  # ditto 而不是 zip -r：保留 bundle 的符号链接、扩展属性和资源分叉。
  # 现在这个 bundle 只有普通文件，换成 zip -r 也过得了校验；以后引入 framework 就不行了。
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

  # 解压回验：防的是「包坏了但当场看不出来」。bundle 要能原样解出来、签名仍然有效、
  # 架构没被 ditto 弄丢。
  TMP="$(mktemp -d)"
  unzip -q "$ZIP" -d "$TMP"
  codesign --verify --deep --strict "$TMP/MacMon.app"
  [ "$(lipo -archs "$TMP/MacMon.app/Contents/MacOS/MacMon")" = "$EXPECTED_ARCHS" ] || {
    echo "✗ 解压后架构不符"; exit 1; }
  rm -rf "$TMP"

  echo "  ✓ $(basename "$ZIP")  $(du -h "$ZIP" | cut -f1)"
done

echo ""
echo "▸ 记录校验和…"
( cd "$OUT" && shasum -a 256 MacMon-"$VERSION"-*.zip > SHA256SUMS )
sed 's/^/  /' "$OUT/SHA256SUMS"

echo "▸ 写 Release 说明…"
cat > "$OUT/release-notes.md" <<EOF
## 下载哪个

| 你的 Mac | 下载 |
|---|---|
| 不确定 / 想省事 | \`MacMon-${VERSION}-universal.zip\`（Apple 芯片 + Intel 都含） |
| Apple 芯片（M1 / M2 / M3 / M4） | \`MacMon-${VERSION}-arm64.zip\` |
| Intel 芯片 | \`MacMon-${VERSION}-x86_64.zip\` |

三个包是同一份代码，区别只在包含哪些架构；universal 体积略大，选错也能跑。

## 首次打开被拦怎么办

产物是 **ad-hoc 签名、未做 Apple 公证**（\`spctl -a\` 的结果就是 rejected），所以首次双击
会被系统拦住。macOS 15 起「右键 → 打开」这个绕过方式已经取消，请改用：

1. 系统设置 → 隐私与安全性 → 拉到最下面 → 「仍要打开」，或
2. 终端执行 \`xattr -dr com.apple.quarantine /Applications/MacMon.app\`

## 校验下载是否完整

\`\`\`
$(cat "$OUT/SHA256SUMS")
\`\`\`

\`shasum -a 256 -c SHA256SUMS\` 通过后再安装。
EOF

echo ""
echo "✓ 完成，产物在 $(pwd)/$OUT"
ls -1 "$OUT"/*.zip | sed 's/^/  /'
echo ""

# 注意：变量后面紧跟中文标点必须写成 ${VAR}，否则 bash 会把全角字符当成变量名的一部分，
# 报 `VERSION，: unbound variable`（踩过）。
cat <<EOF
下一步（两种，任选）：

  A. 网页：项目页 Releases → Draft a new release
     Tag 填 v${VERSION}，把 ${OUT} 下三个 zip + SHA256SUMS 拖进去，
     说明栏直接粘 ${OUT}/release-notes.md 的内容

  B. 命令行（需先 gh auth login）：
     gh release create v${VERSION} ${OUT}/MacMon-${VERSION}-*.zip ${OUT}/SHA256SUMS \\
       --title "MacMon ${VERSION}" --notes-file ${OUT}/release-notes.md
EOF
