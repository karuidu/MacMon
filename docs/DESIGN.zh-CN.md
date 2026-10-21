# 设计笔记

[English](DESIGN.md) · **简体中文**

返回 [README](../README.zh-CN.md)。

这里是 MacMon 的工程日志：塑造了设计的那些约束、试过但失败的方案，以及最终定案的实测数据。
它比 README 详细得多——如果你要改分页容器或采集器，先读这一份。

## 分页：容器是自己画的，不是 `ScrollView`

最早用的是最标准的写法：

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(DashboardPage.allCases) { page in
            PageView(page: page).containerRelativeFrame(.horizontal)
        }
    }
}
.scrollPosition(id: $currentPage)
```

看着对，跑起来不对。macOS 14 上 `scrollPosition(id:)` **只跟随滚动、不驱动跳页**：
用 `MACMON_PAGE=security` 启动时顶栏页签高亮正确落在「安全」，内容却仍停在第 1 页，
连续复现三次。`LazyHStack` 又叠加了一层问题——跳到从未实例化过的页会静默失败。

现在的 `PagePager` 是一个普通 `HStack`，总宽 `width × 5`，靠
`offset(x: -index × width + dragOffset)` 位移：

- **拖拽** —— `DragGesture`，水平判定 `abs(dx) > abs(dy) × 1.5`，用
  `predictedEndTranslation` 处理轻扫
- **滚轮** —— `NSEvent.addLocalMonitorForEvents(.scrollWheel)`，累计 52pt 翻一页。
  这个监听器**不能吞纵向事件**，否则列表就滚不动了
- **键盘** —— `⌘1`–`⌘5` 与 `⌘[` / `⌘]`，改的都是同一个 `NavigationModel.page`

### 页宽不能用内容里的 `GeometryReader` 测

在 `ScrollView` 的内容里测，`GeometryReader` 拿到的是「内容宽度」而不是可视宽度。
五页各按 `width × 5` 算，结果就是 `width × 25`，整块塌掉。要么用
`containerRelativeFrame(.horizontal)`，要么把 `GeometryReader` 包在滚动内容**外面**。

### 导航状态必须和 `AppModel` 分开

`AppModel` 每秒都会发布采集结果。如果菜单命令闭包捕获了它，SwiftUI 会每秒重建一次菜单，
快捷键偶发丢响应。`NavigationModel` 是独立的 `ObservableObject`，一个 tick 之内不会变。

## 首帧不能等全量采集

最早启动时要先跑完「748 个进程 + 21 项启动项验签」才发布第一帧，前几秒整屏「预热中」和一片 0。

现在分三段发布：

1. 快照（约 0.4s）—— CPU、内存、温度、磁盘、网络、电池
2. 进程行
3. 启动项（验签是耗时大头）

三段在同一个串行队列上依次跑，每段完成就跳回主 actor。即使进程扫描很慢，
5 秒内首屏也有真实数据。

`AppModel.start()` 还加了幂等守卫（`guard timer == nil`）。窗口重建会重跑 `onAppear`，
不挡就会起第二个 `Timer`，采集量直接翻倍——这很容易被误判成内存泄漏。

## 布局坑

### `Spacer` 会跟 `frame(maxHeight: .infinity)` 抢空间

hero 卡里数值下方放 `Spacer`，又给折线 `maxHeight: .infinity`，两者平分剩余高度：
折线只剩十几点，看着像「根本没画出来」。改为只让折线吸收剩余高度。

### 折线量纲要跟大数字同量纲

磁盘 hero 卡一度拿「读写速率」当历史却按百分比画，量程成了 227 MB/s，曲线被压成贴底一条线。
现在历史存的是 `usedPercent`。

另外 `Sparkline` 支持非零基线（`ratio = clamp((v − lower) / (upper − lower), 0, 1)`）。
网格线要画在**面积填充之上、折线之下**——先画网格会被面积糊掉。

### 表头与数据行必须共用一套固定列宽

柔性列会让每行按自己的内容各自计算宽度，行与行之间就错位了。`ProcessColumns` 定义一套列宽，
表头和数据行共用，剩余空间单独留给最后一列。

### 温度走势：以当前值为中心的窗口

固定 0–110℃ 时 38℃ 的曲线只占 35% 高度，看着贴底。但直接取历史 `min…max` 更糟：
47℃ 的旧峰值会把区间撑开，当前值又被压回下沿。

所以 `TempScale.range(for:current:)` 的窗口**以当前值为中心**，跨度至少 8℃，
按 5℃ 量化以免每秒换挡：

```swift
let span = max(hi - lo + 2, minSpan)
var lower = floor((cur - span * 0.5) / 5) * 5
var upper = ceil((cur + span * 0.5) / 5) * 5
```

卡片上会标出区间（如 `40–50℃`），否则 2℃ 的正常波动看起来像剧烈起伏。
圆环仍用 0–110 的绝对刻度——环没有轴可以标注。

温度历史必须跳过缺失读数（`if let celsius = ... { append(...) }`），不能拿 `0` 占位：
一个 0 会把算出来的下界永久拉下去。

### 五段 `StackBar`

两个 bug，同一个修法：

- `id = UUID()` 每秒重建，SwiftUI 把每一段都当新视图，动画一直在重启。改成用段名当 id。
- 值为 0 的段仍然占着横向空间，于是出现豁口和比例失真。过滤掉 0 值段，
  再按 `width − gap × (n − 1)` 在**可见**段之间分配宽度。

## 窗口：「打开大屏」点了没反应

菜单栏面板原来的实现是：

```swift
for window in NSApp.windows where window.canBecomeMain {
    window.makeKeyAndOrderFront(nil)
}
```

用红叉关掉窗口后再点，毫无反应。当时的假设是「窗口被销毁了，得重建」。这个假设是错的，
脚本化自检（`--window-selftest`）直接给出了反证：

```
[启动后]        主窗口数=1 visible=true
[hide 之后]     主窗口数=1 visible=false     ← 对象还在，只是不可见
[show 之后]     主窗口数=1 visible=true key=true
[模拟红叉关窗]  主窗口数=1 visible=false     ← 同上，没被销毁
[重建后]        主窗口数=1 visible=true key=true   ← 始终只有一个
```

真正的原因：**窗口一旦 `orderOut` 或被关掉，`canBecomeMain` 就翻成 `false`**，
于是循环体一次都不执行。现在窗口识别条件只剩「有 `.titled` 且不是 `NSPanel`」——
状态栏窗口没有 title，`MenuBarExtra` 面板是 `NSPanel`，这两个条件就够排除其他所有东西。

还有一点：**最小化时 `isVisible` 仍为 `true`**。所以「可见吗」必须写成
`window.isVisible && !window.isMiniaturized`，而且置前之前要先 `deminiaturize`。

### `WindowGroup` 换成 `Window(id:)`

`WindowGroup` 的语义是「再开一个同类窗口」，菜单栏点十次就多十块大屏。
`Window("MacMon", id: WindowID.dashboard)` 是单例 scene。决定按钮文案的状态放在
`WindowBridge` / `DashboardWindowState` 里，订阅
`didOrderOnScreen` / `didOrderOffScreen` / `didMiniaturize` / `didDeminiaturize` /
`didBecomeKey` 以及 app 的 hide/unhide 通知。

注意 macOS 上**没有** `NSWindow.didBecomeVisibleNotification`，要用 `didOrderOnScreen`。

### 隐藏主窗口不要用 `NSApp.hide(nil)`

它会把正在被点击的菜单栏面板一起藏掉，表现成「点一下就整块消失」。用 `window.orderOut(nil)`。

### 窗口落位要夹边界

系统会按上次关闭时的位置恢复窗口，换过显示器之后原点可能落在可见区域之外——
实测出现过 `y = −122`，窗口只露出半截。`place()` 在启动后 0.15s 和 1s 各夹一次，
因为恢复动作可能晚于首次布局。

尺寸只在进程内第一次强制，之后只夹边界；否则窗口重建会把用户拖过的尺寸重置掉。

## 启动项变更监控

### 为什么用 FSEvents 而不是 `DispatchSource`（vnode）

用 vnode source 监听目录意味着每个目录一个 fd。目录一旦被删除或整体替换，source 会自动
cancel、fd 失效，必须在 cancel handler 里重新 open + 重挂；更麻烦的是回调里拿不到是哪个文件变了，
反正也得全量重扫。

`FSEventStreamCreate` 一条流看三个路径，不用管 fd，事件带具体路径。目录被替换时只报一个
`RootChanged`，那正好就是「该重扫了」的信号。

latency 设 0.4s（内核在这个粒度上已经做过合并）。diff 走 1.0s 尾部防抖 + 3.0s 硬上限——
没有上限的话，一次大文件拷贝会不停重置定时器，用户就一直等。

60 个周期一次的全量轮询兜住漏事件：睡眠唤醒和队列积压都会丢 FSEvents。

### 差异键必须用 `plistPath`，不能用 `StartupItem.id`

`StartupItem.id` 是 `kind|label`。两个 Label 相同但分处不同目录的 plist 会互相覆盖；
而改一下 Label 会被判成「删一条 + 加一条」，实际只是改了个名字。

### `unavailableKinds`：假警报雪崩

`try? FileManager.contentsOfDirectory` 在「目录读不到」和「目录不存在」时都返回 `nil`，
和「目录为空」长得一模一样。一次瞬时读取失败就会弹出十几条「启动项被移除」。

所以 `StartupSnapshot` 带上了 `unavailableKinds`，diff 时跳过这些类别的增删判定。
实测把整个 `~/Library/LaunchAgents` `mv` 走：记录数**一条都没多**；恢复后也没有出现
一堆假的「新增」。

### 首次扫描只种基线，绝不告警

`startup` 初值是空快照。拿它去 diff 会一口气产出二十多条「新增启动项」。首扫只种基线。

## 内存口径的推导

活动监视器某一时刻的四个数（截图读数）：

```
App 内存    8.03 GB
联动        1.47 GB
已缓存文件 11.39 GB
空闲        3.11 GB（推算）
合计       24.00 GB
```

反解正确的分项：

```
used = 8.03 + 1.47 = 9.50 GB          （活动监视器的「已使用内存」）
used = internal + wired + compressed   →  internal = 8.03 + purgeable
app  = internal − purgeable      = 8.03
cached = external                = 11.39
free = 24.00 − 9.50 − 11.39      = 3.11
```

自检闭合：`8.03 + 11.39 + 1.47 + 0 + 3.11 = 24.00`。

另外两套看起来自洽、但用在这个界面上就错的公式：

- `used = app + wired + compressed` 正好少算 `purgeable`（这里是 0.8 GB）。
- `cached = external + purgeable` 把 purgeable 算了两次——它本来就在 `internal` 里，
  并且已经因为 `app` 的减法被扣掉了。

所以 `used` 必须是 `internal + wired + compressed`，把 `purgeable` 留在 `used` 内部。
这也是为什么 `--diagnose` 的自检加起来的是
**App + 可清除 + 缓存 + 固定 + 压缩 + 空闲**——六项互斥且穷尽。

`vm_stat` 的页计数要乘 `vm_page_size`；减法要用饱和形式
（`internal > purgeable ? internal - purgeable : 0`），否则一次瞬时不一致就会让 `UInt64` 下溢成天文数字。

还有 `mach_host_self()` 返回的是 send right，必须 `mach_port_deallocate` 释放；
不释放就是每秒漏一个 port。

## 通知

`requestAuthorization` 每个 bundle id 只有一次成功机会。启动路径上弹、用户顺手拒掉，
功能就永久废了。所以只在用户主动打开开关时才申请。

`UNUserNotificationCenter.current()` 在没有 bundle 时会抛
`bundleProxyForCurrentProcess is nil`——`swift run` 和裸二进制正是这种情况。
每处访问都在 `Bundle.main.bundleIdentifier != nil` 之后，
`AppDelegate.applicationDidFinishLaunching` 也在这时提前返回。

`willPresent` 必须返回 `[.banner, .list, .sound]`。不实现的话，通知照样投递，
但 App 在前台时看不见，表现和「功能没做」完全一样。

## 风险评分

两套引擎，共用一套分数类型：

**进程**（`ProcessRiskEngine`）跳过 `/System`、`/usr/*`、`/bin`、`/sbin`、`/Library/Apple`
下的验签——这些二进制随系统而来。其余进程共享一个全局验签预算（`verifyBudget: 50`），
避免 748 行的扫描把循环拖住。规则：可疑路径（`/tmp`、`/var/folders`、`/Library/Caches`）+40、
伪装成系统组件 +35、未签名或失效 +35、ad-hoc +30。

**启动项**（`StartupCollector.assess`）对可执行文件的权重更高，因为启动项是每次开机无人值守运行的。
完整权重表在 README 里。

等级按封顶后的总分切：`<20` 无、`20–39` 低、`40–64` 中、`65–84` 高、`85+` 严重。

可结束性在采集阶段就预先算好，界面可以直接禁用按钮，而不是点下去才被拒：pid ≤ 1、自身、
黑名单进程名（`windowserver`、`launchd`、`coreaudiod` …）、属主不同、内核线程。

## 菜单：SwiftUI 留下的东西

`CommandGroup(replacing:)` 清空的是**组**，不是装它的那个顶层菜单。所以去掉
`.textFormatting`、`.toolbar` / `.sidebar`、`.help` 之后，会剩下三个**空壳菜单**——
「格式」「显示」「帮助」摆在那儿，点开什么都没有。更要命的是 macOS 会绕过 SwiftUI 的命令
构建器，往「编辑」里塞「自动填充」「开始听写…」「表情与符号」，往「窗口」里塞窗口列表。

于是构建完再裁第二遍（`App/MenuLayout.swift`）：

- 整个删掉这个 App 并不具备对应能力的顶层菜单（格式、窗口、帮助），
  并把 `NSApp.windowsMenu` / `NSApp.helpMenu` 置空，免得 AppKit 再往里塞东西；
- 删掉注入的输入辅助项；
- 往「显示」里补回一条全屏（⌃⌘F）——清空 toolbar 组的时候，系统自带的全屏项被一起带走了；
- 合并连续分隔线，去掉首尾分隔线。

两个细节值得记：

- **十个子项是上限。** `CommandsBuilder` 最多接受十个，写十一个就会报
  `extra argument in call`。解法是在同一个 scene 上挂两个 `.commands { }`，而不是嵌套分组。
- **系统菜单的标题跟系统语言走，不跟 App 走。** 界面切到英文后，关于/隐藏/退出、编辑/显示
  仍然是中文。所以 `MenuLayout` 连它们一起改名——按 **action selector** 匹配（selector 不随
  语言变），而不是按标题匹配（标题会变）。裁剪在启动后连做三次（SwiftUI 装配菜单是异步的），
  之后每次切语言再补一次。

另外「服务」子菜单是整块删掉的。里面每一条都来自**别的** App：装了 Xcode 就会出现四个
Instruments 模板（Activity Monitor / Allocations & Leaks / File Activity / System Trace），
它们由系统服务注册表注入到**每一个** App 的菜单里。MacMon 一条都不注册
（`Info.plist` 里没有 `NSServices`），留着它只是个通往别人 App 的门。

## 图标绘制

`assets/make-icon.swift` 就是一个 `swift 文件.swift` 跑在 Core Graphics 上的脚本——
不引 Skia、不引 SVG 工具链，保持「clone 下来就能编译」这件事不破功。

头几次踩了三个坑：

- **翻转 y 会把弧线的角度一起反过来。** 整体做了 translate + scale，坐标按左上原点写，
  但 `addArc` 的角度方向也跟着镜像了：明明写的 138° → −42°，画出来在别处。
  现在用视觉角度（`x + r·cos θ`、`y − r·sin θ`）采样成折线再描边，不用在脑子里换算。
- **线性渐变到端点会戛然而止。** 斜向柔光原本是「裁剪到矩形 + 线性渐变」，因为渐变没有
  延伸到端点之外，方块上留下一道可见的斜向硬边。径向渐变没有这个问题，柔光就换成了径向。
- **渐变描边要靠 `sourceIn` 盖住整条路径。** 在透明层里先按白色描边，再用 `sourceIn`
  灌渐变，就得到渐变描边——但渐变必须覆盖整条路径，没盖到的地方会留白。

小尺寸是**用简化路径单独渲染**的，不是拿母图缩小：16–32px 下真实心电图的两个小波峰只会糊成
两个点，所以 `build-icon.sh` 逐尺寸渲染，生成器在 32px 及以下去掉小波峰并加粗线宽。

## 验收工具

项目没有 test target，四个可脚本化的入口代替它：

- `--diagnose` 打印每个采集器的实机输出加交叉校验（`CProc` 可读性、内存自检偏差、进程解析条数）
- `--window-selftest` 驱动窗口生命周期，每步打印状态
- `--menus` 打印运行中的 `NSApp.mainMenu` 完整结构——标题、快捷键、层级——然后退出。
  没有辅助功能授权，脚本点不开菜单，但能读菜单；于是「服务子菜单到底有没有了」变成一条
  可验证的断言，而不是一张要人肉眼看的截图。
- `scripts/check-l10n.py` 解析 `en` 字典和每一处 `L.t("…")` / `L.f("…")` 调用点，
  「用了但没翻」和「`%@` 数量与译文对不上」都直接返回非零。漏翻在运行时是静默的
  （查不到就退回中文），所以这是覆盖率唯一能自动兜住的地方。解析要留神：长译文会被
  编辑器折到下一行，按行首锚定的正则会漏掉它们——一张其实完整的表会被报出 12 条假缺口。

`.github/workflows/ci.yml` 把两个无头也能跑的入口（`--diagnose`，外加编译与产物校验）当门禁，
把依赖 GUI 的 `--menus` / `--window-selftest` 设成 `continue-on-error`——GitHub 的 macOS
runner 不保证有 WindowServer 会话。断言一律只看结构：每段有输出、进程数大于 0、内存分项合计
偏差在 ±3% 内，因为 runner 是虚拟机，没有电池也没有 HID 传感器。

截图用 `screencapture -l <windowID>`（窗口号从 `CGWindowListCopyWindowInfo` 取），
截出来是「只有窗口 + 阴影」，天然排除系统通知横幅和其他 App。注意多显示器下
`screencapture -x` 只截主屏，副屏要加 `-D 2`。

一个附带的坑：把自编译的辅助二进制放在 `/tmp` 会被本 App 自己的引擎判成高危
（ad-hoc +30、可疑路径 +40，再加其他规则凑到 80），于是它出现在你自己的「高风险进程」截图里。
截图时把辅助工具挪走。

## 构建相关的坑

- 这台机器上 `swift build` 偶尔报
  `sandbox-exec: sandbox_apply: Operation not permitted`——那是 SwiftPM 自己套的沙箱嵌套问题，
  不是代码问题。`swift build --disable-sandbox` 直接过。
- `Package.swift` 把语言模式钉在 Swift 5（`-strict-concurrency=minimal`）：采集层大量使用 C 互操作
  和后台队列，Swift 6 严格并发会产出大量与真实数据竞争无关的标注噪音。
