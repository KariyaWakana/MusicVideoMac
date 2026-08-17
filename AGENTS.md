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
