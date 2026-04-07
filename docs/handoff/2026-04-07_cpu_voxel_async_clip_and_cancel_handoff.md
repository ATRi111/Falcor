# CPU Voxel Async Clip And Cancel Handoff

## 模块职责

把 `VoxelizationPass_CPU` 里最卡 UI 的 `clipAll()` 从 render thread 挪到后台线程执行，并补上最小的可取消状态机，让 CPU 体素化在高模场景下不再长时间卡死 Mogwai。

## 入口与关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_CPU.cpp`
  - 异步状态机在这里：第一次 `voxelize()` 只做输入准备和任务投递，后续 frame 轮询 `std::future`，结果 ready 后再回到 render thread 上传 `gBuffer/polygonRangeBuffer`。
  - `cancelGeneration()` 只设置后台任务的取消标志；真正收口发生在下一次轮询 `future` 时。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_CPU.h`
  - 定义了 `AsyncClipInput / AsyncClipResult / AsyncClipState`，以及取消、状态文本、资源清理接口。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\MeshSampler.h`
  - `PolygonGenerator` 不再绑定 `GlobalGridData`，而是持有一次生成的 grid 快照。
  - `clipMesh()` / `clipAll()` 新增了取消轮询和 triangle 进度计数。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.cpp`
  - 基类只新增了很薄的钩子：`canFinalizeVoxelizationStage()`、`onVoxelizationStageFinalized()`、`canCancelGeneration()`、`getGenerationStatusText()`，用于让异步 CPU backend 暂停基类的后续阶段。

## 当前行为边界

- 已异步：
  - CPU `clipAll()`。
  - UI 中的状态文本和取消请求。
- 仍同步：
  - `LoadMesh` compute pass。
  - GPU->CPU readback。
  - 结果上传回 `gBuffer/polygonRangeBuffer`。
  - `AnalyzePolygon` 和最终写文件。
- 所以这次改动主要改善“界面卡死”，不是把整个 CPU voxelization 变成完全后台流水线。

## 验证

- `E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\plugins\Voxelization.dll`
  - 通过 `cmake --build build\\windows-vs2022 --config Release --target Voxelization --parallel 8` 编译成功。
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\async_cpu_probe_stdout.log`
  - 已命中异步路径日志：
    - `CPU voxelization queued async clipping task for 74600 triangles across 26 instances.`
    - `CPU voxelization async clipping completed in 1218.69 ms with 28892 solid voxels.`

## 后续优先看

- 如果要继续做“真正更快”，优先看：
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_GPU.cpp`
- 如果要继续做“更稳的可取消/后台任务”，优先看：
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_CPU.cpp`
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\MeshSampler.h`
