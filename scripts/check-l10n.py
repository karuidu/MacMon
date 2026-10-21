#!/usr/bin/env python3
"""校验英文翻译表与源码调用是否对齐。

这个项目的中英双语是「以中文原文为键、查不到就退回中文」的查表实现
（见 Sources/MacMon/App/Translations.swift 顶部注释）。好处是漏翻不会崩，
坏处是漏翻**也不会报错**——英文界面里会静静躺着一句中文。

CI 里跑这个脚本，把「漏翻」从肉眼检查变成退出码：

  1. 源码里 `L.t("…")` / `L.f("…")` 用到的字面量键，表里必须都有   → 缺失即失败
  2. 键里带格式符（`%@` / `%.1f` / `%d`）时，译文必须保留同样数量     → 不一致即失败
  3. 表里有、源码里找不到的键                                      → 只警告（可能经变量传参）

用法：
    python3 scripts/check-l10n.py            # 正常校验
    python3 scripts/check-l10n.py -v         # 额外打印未使用的键
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
TABLE = SOURCES / "MacMon" / "App" / "Translations.swift"

# `"键": "值"` —— 键值都允许转义引号。
# 不在行首锚定：长译文会被编辑器折到下一行（键一行、值一行），逐行匹配会漏掉，
# 之前「抽 12 条长译文报漏翻」就是踩了这个坑。
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
# 源码里的查表调用。只收纯字面量键；带 `\(` 插值的跳过（那种写法本项目不允许）
CALL = re.compile(r'L\.([tf])\("((?:[^"\\]|\\.)*)"')
FORMAT = re.compile(r"%(\.[0-9]+)?[@dfsux%]")


def load_table() -> dict[str, str]:
    """解析整个字典字面量。

    先整块取 `static let en: [String: String] = [` 到收尾的 `]`，再整体正则匹配，
    这样跨行的键值对也能抓到；注释行先剔掉，避免注释里的引号被当成条目。
    """
    text = TABLE.read_text(encoding="utf-8")
    body = text.split("static let en: [String: String] = [", 1)[-1]
    body = body.rsplit("]", 1)[0] if "]" in body else body
    body = "\n".join(
        line for line in body.splitlines() if not line.strip().startswith("//")
    )
    entries: dict[str, str] = {}
    for match in ENTRY.finditer(body):
        entries[match.group(1)] = match.group(2)
    return entries


def load_calls() -> list[tuple[str, str, str, int]]:
    """返回 [(文件, 函数名, 键, 行号)]。"""
    calls: list[tuple[str, str, str, int]] = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path == TABLE:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            # 注释里的字样不算调用
            if stripped.startswith("//"):
                continue
            for match in CALL.finditer(line):
                key = match.group(2)
                if "\\(" in key:
                    continue
                calls.append((str(path.relative_to(ROOT)), match.group(1), key, number))
    return calls


def main() -> int:
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    table = load_table()
    calls = load_calls()

    used: dict[str, list[tuple[str, int]]] = {}
    for path, _kind, key, number in calls:
        used.setdefault(key, []).append((path, number))

    missing = sorted(key for key in used if key not in table)
    unused = sorted(key for key in table if key not in used)

    format_bugs: list[str] = []
    for key, value in table.items():
        want = sorted(FORMAT.findall(key))
        got = sorted(FORMAT.findall(value))
        if want != got:
            format_bugs.append(f"  {key!r} → {value!r}  （键 {want or '无'} / 译 {got or '无'}）")

    print(f"表内条目 {len(table)} 条，源码引用 {len(used)} 个键，调用 {len(calls)} 次")

    if missing:
        print(f"\n✗ 漏翻 {len(missing)} 条（英文界面会退回中文）：")
        for key in missing:
            where = ", ".join(f"{p}:{n}" for p, n in used[key][:3])
            print(f"  {key!r}  ← {where}")

    if format_bugs:
        print(f"\n✗ 格式符不一致 {len(format_bugs)} 条（运行时会输出错位或崩溃）：")
        print("\n".join(format_bugs))

    if verbose and unused:
        print(f"\n· 未被源码直接引用 {len(unused)} 条（可能有变量传参，仅提示）：")
        for key in unused:
            print(f"  {key!r}")

    if missing or format_bugs:
        return 1

    print("✓ 翻译表完整，格式符一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
