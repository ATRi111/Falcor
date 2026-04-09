# Profiler Button Deferred Enable Handoff

## 模块职责

修复 Mogwai Graphs 面板里 `Open Profiler` 按钮导致短暂卡顿后直接闪退的问题，并把根因收敛到 profiler 状态切换时机，而不是渲染 graph 或 MultiBunny 脚本本身。

## 根因

- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
  - 之前按钮点击后在 `renderUI()` 里直接执行 `mpRenderer->getDevice()->getProfiler()->setEnabled(true)`。
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Core\SampleApp.cpp`
  - `SampleApp::renderUI()` 一开始用 `FALCOR_PROFILE(..., "renderUI")` 包住整个 UI；如果 profiler 在 `onGuiRender()` 中途才被打开，后半段 profiler window 逻辑会马上执行 `pProfiler->endEvent(pRenderContext, "renderUI")`。
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Utils\Timing\Profiler.cpp`
  - 这一帧的 `renderUI` event 并没有在 frame 开头真正 `start()` 过，所以 `Event::end()` 会碰到 `pActiveTimer == nullptr` 的断言条件，表现就是按钮按下后卡一下然后闪退。

## 当前修复

- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
  - 新增 `mPendingOpenProfiler`。
  - `Open Profiler` 按钮现在只设置 pending flag，不再在当前 `renderUI` 帧里直接启用 profiler。
  - 新增 `beginFrame()` override，在下一帧开始前统一执行 `setEnabled(true)`，避开当前帧尚未闭合的 `renderUI` profiler event。

## 验证

- 定向构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai --parallel 8`
- 代码路径验证：
  - 新逻辑不再在 `onGuiRender()` 中途切换 profiler 状态，而是推迟到 `Renderer::beginFrame()` 调用 extension `beginFrame()` 时生效。
- 本轮没有补自动化 UI 点击回归；当前结论基于最新用户复现现象、Mogwai 运行日志没有标准异常收尾，以及 `SampleApp/Profiler` 代码路径的状态机分析。

## 后续继续时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Core\SampleApp.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Utils\Timing\Profiler.cpp`
