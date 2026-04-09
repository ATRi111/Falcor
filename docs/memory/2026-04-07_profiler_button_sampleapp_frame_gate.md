# 2026-04-07 Profiler Button SampleApp Frame Gate

- 把 Mogwai Graphs 里的 `Open Profiler` 仅延迟到 `Renderer::beginFrame()` 仍然会闪退，因为 `SampleApp::renderFrame()` 里的 `FALCOR_PROFILE("onFrameRender")` 已经早于它开始，下一帧中途再打开 profiler 还是会留下未配对的 profiler scope。
- 这类 UI 触发的 profiler 开关必须提升到 `SampleApp::renderFrame()` 入口，在任何 `FALCOR_PROFILE(...)` scope 开始之前统一应用；本次用 `SampleApp::requestProfilerState()` + `mPendingProfilerState` 规避。
