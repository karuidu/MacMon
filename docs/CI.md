# CI 配置标准（GitHub Actions）

这是一份**复用手册**，不是 MacMon 的专属说明：前半部分是模板和判定规则，后半部分是本项目  
落地时踩到的坑。目标是新项目 30 分钟内配好一套「能挡住真问题、又不会被基础设施噪音烦死」的 CI。

> 本文只有中文版。英文读者看 README 的 `Continuous integration` 一节即可，那里是结论；  
> 这里是过程和模板。



---

## 0. 怎么用

| 你要做的事             | 看哪节              |
| ----------------- | ---------------- |
| 给新项目从零配 CI        | §2 骨架 → §5 适配清单  |
| 判断某个检查该不该当门禁      | §1 原则二           |
| CI 红了但看不出为什么      | §6 分诊表 → §7 排查手段 |
| 想知道 MacMon 为什么这么写 | §8 对照表 → §9 踩坑   |

---

## 1. 五条原则

**① 按「能不能无头跑」分层，不按「重要性」分层。**

CI 机器是没有显示器、没有电池、没有传感器的虚拟机。所以检查要分两类：

- **无头可跑** → 当门禁（编译、单测、静态检查、纯系统 API 的自检）
- **需要 GUI / 需要真硬件** → `continue-on-error: true`，日志上传，红了不挡合并

按重要性分层的后果是：一个「很重要但跑不稳」的检查会天天误报，最后所有人学会无视红叉。

**② 断言查结构，不查数值。**

CI 机器和你的机器的数值永远不一样。只断言这三类东西：

- 某段输出**存在**（`grep -qF "=== 完 ==="`）
- 某个**计数 > 0**（进程数、测试数、产物数）
- 某个**偏差在容差内**（内存分项 ±3%，而不是「必须等于 24.00 GB」）

反例：`assert cpu > 30%` —— 空载的 runner 上必然失败，而且失败得毫无意义。

**③ 区分 `failure` 和 `cancelled`。**

这是最容易被忽略的一条。GitHub 抢不到 runner 时，job 的结论是 **`cancelled`**，不是  
`failure`。把两者都当失败处理，基础设施抖动就会变成「每个 PR 都红」。

**④ 门禁只勾一个聚合 job。**

分支保护里每勾一个 job 名，以后每次加 job 都要回去改规则。用一个 `needs: [...]` +  
`if: always()` 的空 job 收口，只勾它。

> `if: always()` 不能省。省了的话，前面任一 job 失败，聚合 job 会直接被跳过，分支保护  
> 上的检查永远停在 pending —— 比红叉更难受，因为 PR 既不能合也看不到原因。

**⑤ CI 里的命令必须和本地一字不差。**

本地要加的参数（比如某些环境下 SwiftPM 需要 `--disable-sandbox`）就用 `env:` 传进去，  
不要在 CI 里另写一套。两边不一样的命令，差异本身就是下一颗雷。

---

## 2. 骨架（可直接抄）

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:          # 不写 branches，任何目标分支的 PR 都跑
  workflow_dispatch:     # 加一个手动按钮，改 workflow 时可以先点一下试

permissions:
  contents: read         # GITHUB_TOKEN 默认权限很宽，写操作一律收掉

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true   # 连续推 3 次，只跑最后一次

env:
  # 本地和 CI 有差异的参数放这里，命令本身保持一致
  BUILD_ARGS: ""

jobs:
  build:
    name: 构建
    runs-on: ubuntu-latest          # ← 换 §5
    timeout-minutes: 20             # 注意：不含排队时间
    steps:
      - uses: actions/checkout@v7

      - name: 版头
        run: |
          # 把工具链版本打出来。以后「本地过 CI 挂」时，第一眼看这里
          node --version || true
          python3 --version || true

      - name: 安装依赖
        run: |
          # ← 换：npm ci / pnpm i --frozen-lockfile / pip install -r requirements.txt
          echo "无需安装"

      - name: 构建
        run: |
          set -o pipefail                 # 不加这个，管道会吞掉失败
          npm run build 2>&1 | tee build.log   # ← 换构建命令

      - name: 零警告检查
        run: |
          # 只对自家源码生效，别让第三方依赖的 warning 挡住构建。
          # ← 换：这个正则跟编译器输出格式绑定，先在本机跑一遍看警告实际长什么样
          if grep -nE '^(src|app|lib)/.*: warning:' build.log; then
            echo "::error::源码有编译警告"
            exit 1
          fi

      - name: 产物结构校验
        run: |
          set -euo pipefail
          # ← 换：断言产物存在且不是空壳
          test -f dist/index.html
          test -s dist/assets/*.js

      - uses: actions/upload-artifact@v7
        with:
          name: build-output
          path: dist/
          if-no-files-found: error   # 没产物就是失败，别默默放过

  hygiene:
    name: 仓库体检
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v7

      - name: 构建产物没有入库
        run: |
          set -euo pipefail
          # ← 换：dist/ node_modules/ target/ .build/
          if git ls-files | grep -E '^(dist/|node_modules/|target/)'; then
            echo "::error::构建产物被提交了。git rm -r --cached <路径> 后再提交。"
            exit 1
          fi

      - name: .gitignore 仍然挡着
        run: |
          set -euo pipefail
          for entry in 'dist/' 'node_modules/'; do   # ← 换
            grep -qxF "$entry" .gitignore || {
              echo "::error::.gitignore 里少了「$entry」"; exit 1; }
          done

  ci:
    name: CI 通过
    needs: [build, hygiene]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: 汇总结果
        run: |
          build="${{ needs.build.result }}"
          hygiene="${{ needs.hygiene.result }}"
          echo "build=$build  hygiene=$hygiene"

          if [ "$hygiene" != "success" ]; then
            echo "::error::仓库体检未通过（$hygiene）"
            exit 1
          fi

          case "$build" in
            success)   echo "✓ 全部通过" ;;
            cancelled) echo "::warning title=runner 没抢到::构建作业被取消，通常是托管机容量不足，步骤数为 0。重跑即可，不代表代码有问题。" ;;
            *)         echo "::error::构建失败（$build），这是真的没过"; exit 1 ;;
          esac
```

---

## 3. 每个字段为什么这么写

| 字段                                      | 理由                                                                |
| --------------------------------------- | ----------------------------------------------------------------- |
| `pull_request` 而非 `pull_request_target` | 前者只给 fork 来的代码**只读** token，读不到 secrets、推不动仓库。后者会把 secrets 交给不可信代码 |
| `permissions: contents: read`           | `GITHUB_TOKEN` 默认可能带写权限，收窄到只读是零成本的防御                              |
| `concurrency` + `cancel-in-progress`    | 同一个分支连推 3 次，旧运行自动取消，省额度也省时间                                       |
| `timeout-minutes`                       | **只算执行时间，不算排队**。排队有 GitHub 自己的 15 分钟 acquire 上限，改不了               |
| `needs` + `if: always()`                | 见 §1 原则四的注                                                        |
| `if-no-files-found: error`              | 默认是 `warn`，产物没生成也能绿——这是最典型的假绿来源之一                                 |
| `uses: ...@v7`                          | 用**主版本号 tag**，不用 `@main`（会随机挂），也不用 `@<commit sha>`（除非要防供应链攻击）     |

Action 版本要跟着升级。GitHub 弃用旧 Node 运行时的方式是「强制抬到新版本 + 在 annotation  
里报 warning」，`actions/checkout@v4` 就踩过（Node 20 → Node 24）。看到  
`Node.js XX is deprecated` 就去翻 action 的 release notes，确认 breaking change 与自己无关后再跳。

---

## 4. 断言的四种写法

**① 关键行存在** —— 最适合命令行工具的输出

```bash
for key in "=== 完 ===" "CPU  :" "内存  :"; do
  grep -qF "$key" out.log || { echo "::error::输出缺少「$key」"; exit 1; }
done
```

**② 数值容差** —— 用 `awk`，别用 `bc`（不保证装）也别用浮点比较的 shell 内置

```bash
drift=$(sed -nE 's/.*偏差 ([-+]?[0-9]+\.[0-9]+)%.*/\1/p' out.log | head -1)
[ -n "$drift" ] || { echo "::error::没读到偏差"; exit 1; }
awk -v d="$drift" 'BEGIN { exit (d <= 3 && d >= -3) ? 0 : 1 }' || {
  echo "::error::偏差 ${drift}% 超出 ±3%"; exit 1; }
```

**③ 命名产物不许入库** —— `git ls-files` 比 `find` 准，它只看已跟踪文件

```bash
if git ls-files | grep -E '^(dist/|\.next/|target/)'; then ... exit 1; fi
```

**④ 假绿排查：查日志，别只查退出码**

如果被测程序自己 `exit(0)` 兜底（很多 CLI 工具在「没数据」时也算正常退出），只看退出码  
永远是绿的。这时候必须 grep 它的输出里那句「完成标志」。

MacMon 就吃过这个：`--menus` 在 `NSApp.mainMenu == nil`（无 GUI 会话）时仍然 `exit(0)`，  
所以 CI 里查的是日志里的 `MENU done`，不是退出码。

---

## 5. 适配到新项目：改这里

| 位置        | 骨架里的值                     | 换成                                                                                     |
| --------- | ------------------------- | -------------------------------------------------------------------------------------- |
| `runs-on` | `ubuntu-latest`           | `macos-latest`（要 Xcode）/ `windows-latest` / `macos-26-intel`（arm64 池挤时）                |
| 安装依赖      | 空                         | `npm ci`、`pnpm i --frozen-lockfile`、`pip install -r requirements.txt`、`bundle install` |
| 构建        | `npm run build`           | 你的构建命令                                                                                 |
| 版头        | `node --version`          | 对应工具链版本，方便复现环境                                                                         |
| 产物断言      | `test -f dist/index.html` | 你的产物路径 + 「非空」检查                                                                        |
| 体检忽略列表    | `dist/` `node_modules/`   | 你的构建目录                                                                                 |
| 自检命令      | 无                         | 有 CLI 自检就加（`--diagnose` 这种）；有测试就跑测试                                                    |

**要不要开缓存？** 判据是「装依赖的时间占比」。

- 依赖几秒钟装完（零依赖 / 单一工具链）→ **别开**。缓存失配时报的错（旧产物和新 manifest  
  对不上）比省下的时间贵得多。MacMon 就故意不缓存 `.build`。
- 依赖要装几十秒到几分钟（`node_modules`、`~/.m2`、pip wheel）→ 开 `actions/cache`，  
  key 用 lock 文件哈希：`${{ hashFiles('**/pnpm-lock.yaml') }}`。

**要不要 matrix？** 只有在「多平台/多版本都必须过」时才用。matrix 是**全部**组合都要成功，  
一个版本挂了整片红——对个人项目通常是负担。

---

## 6. 分诊表：看到什么 → 是什么

| 现象                                                                          | 结论                                                   | 处理                                           |
| --------------------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------- |
| `The job was not acquired by Runner of type hosted` + **步骤数为 0** + 恰好 15 分钟 | **容量问题，不是代码问题**                                      | 重跑；长期如此换 runner 标签（arm64 → intel）            |
| `cancelled` 但步骤跑了几个                                                         | 被 `concurrency` 取消，或 `timeout-minutes` 到点            | 查是否有并发推送；调 timeout                           |
| 步骤绿但产物/日志没生成                                                                | 命令后面跟了 `\|\| true`，或 `if-no-files-found` 用了默认 `warn` | 去掉 `\|\| true`，改 `error`                     |
| 本地过、CI 挂                                                                    | 环境差异：PATH、编码、时区、工具链版本                                | 版头步骤打印版本；必要时固定 runner 版本                     |
| annotation 里一堆 `Node.js XX is deprecated`                                   | action 版本旧                                           | 升到最新主版本，先读 release notes 的 breaking change   |
| 分支保护一直 pending，PR 合不了                                                       | 聚合 job 被跳过（缺 `if: always()`），或名字改了                   | 补 `always()`；检查勾选的 job 名与 yml 里 `name:` 是否一致 |

---

## 7. 排查手段（UI 上看不全的时候）

公开仓库这两个接口**匿名可读**，不用 token，比翻网页快：

```bash
# 每个 job 的结论、runner 名、步骤列表、起止时间
#   runner_name 为空 + steps 长度为 0 + 时长约 15 分钟 ⇒ 就是没抢到机器
curl -s "https://api.github.com/repos/<owner>/<repo>/actions/runs/<run_id>/jobs"

# GitHub 自己写的注解（比 UI 上展开的「Annotations」全）
curl -s "https://api.github.com/repos/<owner>/<repo>/check-runs/<check_run_id>/annotations"
```

`check_run_id` 从上面第一条的返回里拿不到，得先查  
`/repos/<owner>/<repo>/commits/<sha>/check-runs`。

---

## 8. MacMon 的实际配置（对照 §2 骨架）

| job                                | 门禁？                    | 内容                                                                                                     | 为什么                    |
| ---------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------ | ---------------------- |
| `构建与打包`                            | 是                      | 零警告编译 → `build-app.sh` → bundle 身份 → 图标 10 个尺寸反解 → `Package.swift`/`Info.plist` 版本一致 → `--diagnose` 断言 | 这些都是无头可跑的              |
| 　└ `--menus` / `--window-selftest` | 否（`continue-on-error`） | 打印菜单树、驱动窗口生命周期                                                                                         | 需要 WindowServer，托管机不保证 |
| `仓库体检`                             | 是                      | 产物未入库 + `.gitignore` 看门狗 + 翻译表完整性                                                                      | 跑在 ubuntu，6 秒          |
| `CI 通过`                            | 是（分支保护只勾这个）            | 汇总，`cancelled` 放行                                                                                      | 见 §1 原则三、四             |

实际耗时：macOS 那个 70 秒 / 16 步，体检 6 秒，汇总 2 秒，整条 79 秒。

三条 MacMon 特有的断言值得抄：

1. **图标尺寸数**：反解 `.icns` 数 PNG，少于 10 个就失败——挡住「拿 1024 母图缩全部尺寸」  
   的退化（小尺寸会糊）。
2. **两处版本必须一致**：`Package.swift` 的 `platforms` 和 `Info.plist` 的  
   `LSMinimumSystemVersion`。只改一个会让「SwiftPM 说 14.0、Finder 说别的」这种错位溜过去。
3. **翻译表覆盖率**（`scripts/check-l10n.py`）：查漏翻和 `%@` 数量不一致。漏翻在运行时  
   是静默退回原文的，只有 CI 能兜住。

---

## 9. 踩坑清单（本项目的真实记录）

1. **`macos-latest` 现在等于 macOS 26 arm64，会排队到超时。** 表现：job 结论 `cancelled`、  
   `runner_name` 为空、步骤数 0、耗时恰好 15 分钟。注解里 GitHub 自己写着  
   「Due to capacity constraints...」。备选标签 `macos-26-intel`（x64）。
2. **`--menus` 恒返回 0** → 必须查日志。任何「自己吞错误」的程序都适用 §4 的第 ④ 条。
3. **`actions/checkout@v4` 报 Node 20 弃用** → 升 v7。v7 唯一的 breaking change 是禁掉  
   `pull_request_target` / `workflow_run` 下 checkout fork 代码，用 `pull_request` 就不受影响。
4. **`set -o pipefail` 不能忘**：`命令 | tee log` 之后，前面失败、管道最后一条成功，步骤照样绿。
5. **别用 `gh` 之外的私有 API 猜状态**：`jobs` / `annotations` 两个接口足够分诊。
6. **`ubuntu-latest` 会静默升版本**（2026-10-19 起是 Ubuntu 26）。只在脚本里依赖标准工具  
   （`python3`、`git`、`grep`），别依赖某个特定预装版本。

---

## 10. 成本与边界

|             | 公开仓库                  | 私有仓库         |
| ----------- | --------------------- | ------------ |
| Linux 分钟    | 免费不限                  | 按额度扣，1×      |
| macOS 分钟    | 免费不限                  | 按额度扣，**10×** |
| Windows 分钟  | 免费不限                  | 按额度扣，2×      |
| 并发（Free 计划） | 20 个 job，其中 macOS 5 个 | 同            |
| Artifact 保留 | 90 天（可调到 1–90）        | 同            |

所以：**能跑在 `ubuntu-latest` 的活就别丢给 macOS**。MacMon 的体检和翻译检查放 ubuntu 上，  
6 秒跑完；如果放 macOS，私有仓库里要按 60 秒算。

---

## 11. 出包与分发：为什么不能 `git add` 那个 `.app`

写这一节是因为一个几乎人人都会误判的点：以为 `MacMon.app` 是个「文件」，可以直接传到 GitHub
让别人下载。

**它是目录。** `ls -ld MacMon.app` 返回 `drwxr-xr-x`。GitHub 的 Release 资产只收**文件**；
而 `git add` 会把整棵目录树逐个文件塞进历史——里面那个可执行文件每次构建都变，仓库体积会
随着每次提交膨胀，事后清理要 rewrite 历史。

四种分发路径的现实：

| 方式 | 下载者会不会被拦 | 成本 | 说明 |
|---|---|---|---|
| 只发源码，让用户自己编 | 不涉及 | 0 | 本地构建没有 quarantine 属性，最稳 |
| Release + ad-hoc 签名 zip | **会拦**，需手动绕过 | 0 | 想要「下载即用」就得接受这一步 |
| Developer ID 签名 + 公证 | 不会，双击即开 | $99/年 | 认真分发才值得 |
| Mac App Store | — | $99/年 | 不可能：它读全系统进程，过不了沙盒 |

### 这个项目上的实测数据

```
codesign -dvvv   →  Signature=adhoc   TeamIdentifier=not set
spctl -a -vvv    →  rejected
加 quarantine 后 →  rejected        ← 下载者双击看到「无法验证开发者」的真正原因
bundle 5.8 MB（universal）  →  zip 2.5 MB
```

`spctl -a` 返回 `rejected` 不是因为签名坏了（`codesign --verify` 是过的），而是因为没有
**Developer ID 证书**、也没送 Apple **公证**。两件事都要有才不会被拦。

### 出一版发行包

默认一次出三种架构，让下载者按自己的芯片挑：

| 包的结尾 | 给谁 | 体积 |
|---|---|---|
| `-universal.zip` | 不确定、想省事（Apple 芯片 + Intel 都含） | 2.5 MB |
| `-arm64.zip` | M1 / M2 / M3 / M4 | 1.8 MB |
| `-x86_64.zip` | Intel 芯片 | 1.8 MB |

```bash
./scripts/make-release.sh                     # 三份都出
VERSION=1.1.0 ./scripts/make-release.sh       # 指定版本
TARGETS=universal ./scripts/make-release.sh   # 只出 universal
TARGETS=split ./scripts/make-release.sh       # 只出两个单架构包
```

**只编译一次，然后切。** 先 `swift build --arch arm64 --arch x86_64` 拿到 fat 二进制，
再用 `lipo -thin arm64| -thin x86_64` 切出单架构。好处是三份包代码完全同源（同一份二进制
的切片），不用编三遍；代价是 `lipo -thin` 会让签名失效，所以每个包都要重签——这一步由
`build-app.sh` 的 `codesign --force --deep --sign -` 完成，回验阶段会复查。

脚本做五件事：universal 编译 → 逐架构组装 bundle（复用 `build-app.sh`，避免 Info.plist
两处漂移）→ `ditto` 打包 → **解压回验**（重解一遍再跑 `codesign --verify` 和 `lipo`，
防止打出坏包还浑然不知）→ 生成 `SHA256SUMS` 和 `release-notes.md`。

打包为什么用 `ditto` 而不是 `zip -r`：后者会跟随符号链接、丢扩展属性和资源分叉。现在这个
bundle 只有 5 个普通文件，实测 `zip -r` 也过得了签名校验；但一旦引入 framework（内部全是
符号链接）就会坏。

### 推 tag 自动发版

`v*` 的 tag 会额外触发 `release` job（平时推 main、开 PR 不碰它）：

```bash
git tag v1.0.0
git push origin v1.0.0        # 或 git push --tags
```

这个 job 做四件事：`VERSION=${GITHUB_REF_NAME#v}` 跑同一个脚本（版本号从 tag 取，不然每个
release 里都是 1.0.0）→ 把校验和写进运行摘要 → `gh release create` 建 Release 并挂上三个
zip（Release 已存在时改为 `gh release upload --clobber` 补传，所以重跑不会报错）→ 再留一份
workflow artifact 存档。

三个设计点：

- **`permissions: contents: write` 只开在这个 job 上**，全局仍是只读。发版需要写权限，但没必要
  让每个跑 PR 代码的 job 都有。
- **`needs: [build]`**：build 挂了就不该发版。代价是 build 因容量被 cancelled 时它也会被跳过
  ——重跑一次，比发出去一个没验证过的包强。
- **不自动打 tag。** tag 由人推，CI 只负责「tag 指向的 commit → 包 → Release」。反过来做
  （CI 里造 tag）会让「谁是那一版的源码」变得模糊。

两个必须知道的细节：

1. **哈希每次都不一样。** `ditto` 保留文件 mtime，重新构建 → 重新打包，SHA-256 必变。
   所以「以 `dist/SHA256SUMS` 为准」，别拿不同时间的包互相对哈希。
2. **本机跑脚本主要用于验证流程**，正式发布交给 tag job，产物和 commit 天然一一对应。

### 以后要做公证的话

前提是 Apple Developer Program（$99/年）。技术路径：

```bash
codesign --force --options runtime --sign "Developer ID Application: …" --timestamp MacMon.app
xcrun notarytool submit MacMon.zip --apple-id … --team-id … --password … --wait
xcrun stapler staple MacMon.app
```

CI 里需要 `APPLE_ID`、`APP_SPECIFIC_PASSWORD`、`TEAM_ID` 三个 secrets。开 hardened runtime
之后要复查 entitlements：这个 App 用 `sysctl` / `libproc` 读别的进程，属于普通读取，不需要
特权 entitlement；但 `ServiceManagement`（登录项）那块在 hardened runtime 下的行为得实测
一遍再发。
