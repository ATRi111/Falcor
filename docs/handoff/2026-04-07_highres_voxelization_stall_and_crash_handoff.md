# Highres Voxelization Stall And Crash Handoff

## 模块职责

解释高分辨率体素化为什么会长时间卡住并最终崩溃，并把修复收敛到当前 CPU/GPU 生成路径、内存模型和溢出风险。

## 结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.h`
  - `UpdateVoxelGrid()` 按最长边分辨率推导整张体素网格，`totalVoxelCount` 会随分辨率近似立方增长。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.cpp`
  - 生成流程仍是同步执行的；写文件前后都有 `submit(true)`，主线程会等待 GPU/拷贝完成。
  - 现在新增了统一失败态、峰值工作集预估、`dense voxel` / `peak working set` 安全阈值，以及 `std::bad_alloc` / 运行时异常兜底。
  - UI 会显示 `Estimated Peak Working Set` 和最近一次失败原因；生成前会先做预检查，不再盲目开跑。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
  - 每个实体体素都会做 `LEBEDEV_DIRECTION_COUNT / 2 = 13` 个方向、每方向 `sampleFrequency` 次射线估计；这是高 sample frequency 时最容易把时间拉爆的阶段。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_CPU.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\MeshSampler.h`
  - CPU 路径会把 mesh 数据回读到 CPU，再在主线程单线程 `clipAll()`，同时维护整块 `vBuffer` 和 `polygonArrays`；高分辨率下容易吃满内存并让 Mogwai 长时间无响应。
  - `VoxelizationPass_CPU::estimatePeakWorkingSetBytes()` 现在会把 mesh staging/readback 也计入安全预估。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_GPU.cpp`
  - GPU 路径虽然把大头采样挪到 GPU，但仍会回读完整 `vBuffer` 和 `polygonCountBuffer` 到 CPU，再为 polygon 分组预分配，所以并不是全异步、零回读。
  - 现在会显式分配 `overflowFlag`，把 `maxSolidVoxelCount` 传入 shader，并在回读后检查 overflow；命中时会 `failGeneration()` 并打印容量/实际体素数。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\SampleMesh.cs.slang`
  - 新实体体素 offset 现在会先和 `maxSolidVoxelCount` 做上界检查；如果实际实体体素数超过 `solidRate` 预估容量，会打 `overflowFlag` 并跳过写入，而不是继续写越界。

## 已完成修复

- 高分辨率生成前预检查：
  - 空网格、32-bit 索引上界、`64M` 体素 dense index 安全阈值、`3 GiB` 峰值工作集安全阈值。
- 统一失败处理：
  - `voxelize()` / `sample()` / `write()` 三阶段异常会中止本轮生成，字典输出改为未完成态，避免继续级联。
- GPU overflow guard：
  - shader 侧用 `overflowFlag + maxSolidVoxelCount` 截住新 offset，CPU 侧回读后再次核验并输出明确 warning。

## 验证

- `E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\plugins\Voxelization.dll`
  - 通过 `cmake --build build\\windows-vs2022 --config Release --target Voxelization --parallel 8` 编译成功。
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\highres_guard_stdout.log`
  - 已命中 CPU 预检查：`CPU voxelization aborted: dense voxel index volume would reach 500 MiB for 131072000 voxels.`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\Voxelization_GPU_overflow_probe.py`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\gpu_overflow_probe_stdout.log`
  - 通过临时验证脚本把 `solidRate` 压到 `0.0001`，已命中 GPU guard：`GPU voxelization aborted: solid-voxel allocation overflowed the preallocated capacity (28892 > 27).`

## 对“要不要改异步多线程”的判断

- 仍然值得做，但现在不再是阻塞问题。
- 异步后台生成或 CPU 多线程 clip 只能改善“卡住很久”的体验，不能自动解决：
  - 体素网格和 `vBuffer` 的立方级内存膨胀；
  - `AnalyzePolygon` 的高采样成本；
  - GPU 路径容量估计不足导致的越界写。
- 如果后续继续做，优先把后台任务和取消机制放到 `VoxelizationPass.cpp` 的生成状态机附近，不要先去拆 shader 或文件格式。

## 后续优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_CPU.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_GPU.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\MeshSampler.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\SampleMesh.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
