# Profiler Button SampleApp Frame Gate Handoff

## 模块职责

修复 Mogwai Graphs 面板 `Open Profiler` 按钮在第一次修复后仍会卡顿闪退的问题，并把 profiler 状态切换入口统一收束到 `SampleApp` 的帧起点。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Core\SampleApp.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Core\SampleApp.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Utils\Timing\Profiler.cpp`

## 根因与当前修复

- 只把按钮逻辑推迟到 `MogwaiSettings::beginFrame()` 还不够早，因为 `SampleApp::renderFrame()` 在调用 `Renderer::onFrameRender()` 前已经会进入 `FALCOR_PROFILE("onFrameRender")` 等 profiler scope；profiler 若在同一帧中段才启用，仍可能在 scope 退出时命中未开始 timer 的异常路径。
- 现在 `MogwaiSettings` 只调用 `mpRenderer->requestProfilerState(true)`，真正的 `setEnabled(true)` 在 `SampleApp::renderFrame()` 里、任何 profiler scope 开始前执行；同时删掉了 `MogwaiSettings` 的 `beginFrame()` pending 开关逻辑。

## 验证

- 定向构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai --parallel 8`
- 人工回归通过：
  - 重新启动 `run_MultiBunny_Voxel.bat` 后，由用户手动点击 `Open Profiler`，本轮确认不再闪退。

## 后续继续时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Core\SampleApp.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Utils\Timing\Profiler.cpp`
