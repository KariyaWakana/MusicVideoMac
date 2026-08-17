# MusicVideoMacApp 架构规范与已知坑点

这份文档记录了项目中经过反复验证得出的血泪教训和底层原则，任何参与此项目的 AI 或开发者在修改代码前都必须遵守。

## 1. 焦点竞争与死锁 (AppKit Modal Deadlock)
**场景**：在使用 `NSColorPanel`、`NSFontPanel` 或者拖拽文件时，AppKit 会进入特殊的模态事件循环（Modal Event Loop）。
**坑点**：如果在这个时间点，后台任务（例如视频渲染队列 `RenderQueueManager`）突然抛出一个打断当前上下文的操作（比如强制激活访达 `NSWorkspace.shared.activateFileViewerSelecting` 或弹出 `NSAlert`），主线程的事件循环就会被打断，导致整个 App 直接卡死（Deadlock）。
**规则**：
- **绝对禁止**后台任务在完成后强制抢占焦点或弹窗。
- 任务完成的提示应该使用 `UNUserNotificationCenter`（系统级通知，不抢焦点）或在 UI 上默默更新状态。
- 若需要打开访达等操作，必须在 UI 上提供一个按钮（例如 🔍 图标），由用户**主动点击**触发。

## 2. 跨上下文状态污染 (Global State Bleed)
**场景**：用户先载入了一个包含多张碟片的专辑 A（例如修改了 Disc 1 的独立颜色），随后拖入了一个全新的单碟专辑 B（如单曲 EP）。
**坑点**：如果 View Model (`AppViewModel`) 里的全局字典（如 `discBgColors`、`discTextColors`）没有在 `resetAll()` 里被彻底清空，专辑 B 就会错误地继承专辑 A 的颜色设置。单曲专辑会被 iTunes API 误标或自动标记为 Disc 1，从而错误地调用了被污染的 `discBgColors["1"]`。
**规则**：
- 只要是重新加载实体（载入新文件夹、重新扫描等），**必须确保清空所有全局缓存状态**（包括但不限于颜色字典、数组等）。
- **防御性编程**：不要仅依赖状态清空。在应用“每个碟片独立颜色 (`separateDiscColors`)”这类的逻辑时，底层代码必须多做一层校验：比如判断 `uniqueDiscs.count > 1` 才会应用独立颜色逻辑，防止因开关在 UI 上被隐藏但 UserDefaults 中仍为 true 导致的越权套用。

## 3. VFR/CFR 视频渲染策略
**场景**：使用 `AVAssetWriter` 直接将静态画面加上音频渲染为 MP4 时，遇到速度极慢以及在 Bilibili / YouTube 掉帧、卡顿的问题。
**坑点与解决方案**：
- **速度极慢**：让硬件编码器一行行去压制完全不动的画面（比如1小时）非常愚蠢（耗时25分钟）。
  - **解法 (Segmented Passthrough Assembly)**：利用 `AVMutableComposition` 和 `AVAssetExportPresetPassthrough`，先只渲染出 1 秒的极短静态素材和转场动画，然后在内存轨道上对这些切片做无数次循环拼贴，速度从 25 分钟降至 1 秒。
- **平台重新压制掉帧**：如果静态画面只塞了 1 帧，视频网站的转码器会以为是坏文件并强制丢帧。
  - **解法**：即使是静态画面，也必须维持一个“伪基准帧率”（例如设置 VFR 基准为 15fps~30fps），骗过平台的转码器。

## 4. UI 刷新与 @AppStorage 的时序问题
**场景**：通过自动提取封面颜色（`ColorExtractor`）改变了 `@AppStorage` 保存的 `bgR, bgG, bgB`。
**坑点**：如果先载入了包含自定义颜色的 `.mv_settings.json`（比如用户保存的主题），随后封面图片异步加载完成触发了 `onChange(of: coverImage)`，自动提取颜色的逻辑就会无情覆盖掉用户原本保存的 `.mv_settings.json` 设置。
**规则**：
- 颜色提取等“破坏性自动推断”逻辑，应当慎重执行。目前的逻辑是 JSON 设置覆盖后如果不巧被后加载的封面触发 `extractColors`，可能会擦除用户自定义值。这在开发新功能时要极其小心竞态问题。
# MusicVideoMacApp: 设计哲学与代码美学 (Design Philosophy & Code Aesthetics)

在解决了一系列诸如“UI死锁”、“状态串位（串色）”、“渲染性能瓶颈”以及“异步数据竞态”等复杂且底层的 Bug 后，我们有必要从更高维度的视角来审视这些错误。

这些错误并非偶然的笔误，而是**架构决策和编码哲学上的系统性偏差**。为了让 `MusicVideoMacApp` 能够极其稳定、优雅地运行，我们需要确立一套核心的“代码哲学”。

这不仅仅是给 AI 助手看的，更是为了确保 App 拥有**“极客级的性能与苹果级的优雅”**。

---

## 一、 状态沙盒化：互不信任的领域边界 (Contextual Isolation & Zero Trust State)

**引发思考的 Bug**：单碟专辑错误地继承了上一张多碟专辑“Disc 1”的自定义颜色（状态串色）。
**底层原因**：过度依赖长生命周期的全局 `ViewModel` 进行状态变异（Mutation）。`resetAll()` 只是在给一个脏杯子倒水清洗，却遗漏了角落里的污渍（`discBgColors`）。

### 🛠 代码美学
1. **即用即毁 (Ephemeral Context)**：不要试图“清洗”一个复杂的全局状态。当用户拖入一个新文件夹时，应当将其视为一个全新的“会话（Session）”。理想的做法是实例化一个全新的领域模型（Domain Model），旧的直接被 ARC（自动引用计数）回收，而不是手动地去 `removeAll()` 一堆属性。
2. **默认防守 (Defensive by Default)**：任何特殊逻辑（如“每碟独立颜色”）在应用前，必须对其所处的环境进行二次校验（例如：强校验 `uniqueDiscs.count > 1`）。不要仅仅因为 UI 开关处于开启状态就无脑执行逻辑。

---

## 二、 敬畏用户的交互空间 (Respect the User's Space)

**引发思考的 Bug**：用户正在使用 `NSColorPanel` 愉快地挑选颜色，后台渲染完成突然强行唤醒 Finder，打破了模态事件循环，导致 macOS 死锁卡死。
**底层原因**：后台任务产生了僭越（Overstepping），试图越权干涉前端的主线程 UI 焦点。这是一种“开发者本位”的傲慢设计。

### 🛠 设计规范
1. **静默服务 (Silent Servants)**：后台队列和底层运算必须像影子一样安静。它们只负责产生数据、更新状态字（State），**绝对不允许**直接调用任何强制夺取系统焦点的 API。
2. **状态驱动而非事件驱动 (State-Driven over Event-Driven)**：后台渲染完成，不应该发送“打开文件夹”的动作指令，而是将 `isCompleted` 状态设为 `true`。由 UI 层观察到这个状态后，渲染出一个按钮（如 🔍 放大镜），**将最终的选择权交还给用户**。
3. **安全触达 (Safe Reach-Out)**：如果必须打断或提醒用户，使用系统规定的非侵入式通道（如 `UNUserNotificationCenter`），绝不硬抢鼠标焦点。

---

## 三、 极客务实主义：透视数据本质 (Geek-level Pragmatism)

**引发思考的 Bug**：1小时的专辑，使用苹果标准的 `AVAssetWriter` 老老实实逐帧渲染，耗时25分钟，效率极低。
**底层原因**：被系统提供的高层 API 束缚了想象力。标准 API 假设你在渲染一部每一帧都在变化的电影，但我们的数据本质上是“99%的时间只有一张静态图片在播放音频”。

### 🛠 代码哲学
1. **超越 API，直击数据本源 (Look Beyond the SDK)**：不要盲目迷信官方 API 的标准用法。当我们意识到“视频的大量时间其实只是不变的 H.264 P/IDR 帧”时，我们放弃了“逐帧渲染”，转向了“积木无损拼接法 (Segmented Passthrough)”。
2. **在“笨办法”和“奇技淫巧”中找到优雅**：为了规避视频平台对 VFR（可变帧率）的苛刻审查，我们没有选择重构整个 CFR 渲染管线，而是巧妙地在底层容器(`AVMutableComposition`)里循环复制 1 秒钟的静态数据块。用最轻量的内存操作，换取了几十倍的性能提升。这，就是极客美学。

---

## 四、 绝对的真理阶级 (Deterministic Truth Hierarchy)

**引发思考的 Bug**：用户保存的 `.mv_settings.json` 被随后异步加载出来的封面所触发的“自动颜色提取”逻辑给无情覆盖了。
**底层原因**：两个不同的异步时间流（读本地文件 vs 网络下载封面），试图同时修改同一个状态变量。产生了所谓的“异步竞态（Race Condition）”。

### 🛠 架构规范
在面对多数据源输入时，系统必须拥有一套不可动摇的**真理阶级（Priority Hierarchy）**。从高到低排列：
1. **Top 1: 用户的主动覆盖 (User Explicit Override)** —— 用户在 UI 上手动选的颜色。
2. **Top 2: 本地配置文件 (.mv_settings.json)** —— 之前保存的历史心血。
3. **Top 3: 网络/iTunes 爬取数据 (Network Inference)** —— 推断出的曲目、碟片信息。
4. **Top 4: 算法自动推导 (Algorithmic Extraction)** —— 比如看封面提取主色调。

**实践规则**：低阶级的数据流入时，**必须**检查高阶级是否已经宣告了它的真理。如果 `.mv_settings.json` 已经说了“我要用自定义颜色”，哪怕晚了半分钟加载出来的封面再漂亮，自动提取颜色的算法也必须**乖乖闭嘴**，无权覆盖。

---

## 结语
优秀的工具不仅是代码的堆砌，更是对系统边界的敬畏、对数据本质的洞察、以及对用户选择权的尊重。
这份《设计哲学》将是 `MusicVideoMacApp` 未来一切重构和新功能开发的试金石。
