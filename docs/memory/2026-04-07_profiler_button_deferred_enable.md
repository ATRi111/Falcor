# 2026-04-07 Profiler Button Deferred Enable

- 如果在 Mogwai 的 `onGuiRender()` / Graphs 面板按钮回调里直接 `setEnabled(true)` 打开 profiler，`SampleApp::renderUI()` 同一帧后半段会立刻尝试 `endEvent("renderUI")`，但这一帧开始时 profiler 还是关闭的，导致 `Profiler::Event::end()` 命中未启动 timer 的断言并闪退。
- Graphs 面板里的 `Open Profiler` 必须延迟到下一帧 `beginFrame()` 再真正启用 profiler，避免在当前 `renderUI` 作用域中途切换 profiler 状态。
