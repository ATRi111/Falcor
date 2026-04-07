# MultiBunny Voxel Graph And Profiler Button Handoff

## 模块职责

让 `run_MultiBunny_Voxel.bat` 对应的 `VoxelOnly` 入口改为真正的纯 voxel render graph，同时在 Mogwai 的 `Graphs` UI 增加一个按钮，按下即可打开现有的 Profiler 窗口。

## 当前状态

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - 新增 `HYBRID_PIPELINE_MODE` 解析，支持在保留现有 `HYBRID_OUTPUT_MODE` 语义的同时单独切 graph pipeline。
  - 新增 `render_graph_voxel_view()`，只包含：
    - `VoxelizationPass`
    - `ReadVoxelPass`
    - `RayMarchingDirectAOPass`
    - `ToneMapper`
  - `create_voxel_chain()` 新增 `instance_route_mask` 参数；纯 voxel graph 会传 `ALL_ROUTE_MASK`，不再沿用 hybrid 的 `Blend|VoxelOnly` selective execution 语义。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - 默认增加 `HYBRID_PIPELINE_MODE=voxel`，因此 `run_MultiBunny_Voxel.bat` 启动后会直接走 pure-voxel graph，不再挂 mesh / hybrid passes。
  - `Voxelization_MultiBunny_VoxelRoute.py` 没改，`run_HybridMeshVoxel.bat voxel` 仍保持原先 hybrid/route 语义。
- `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
  - 在 Graphs 面板顶部把按钮排布改成：
    - `Edit`
    - `Open Profiler`
    - `Remove`
  - `Open Profiler` 直接调用 `mpRenderer->getDevice()->getProfiler()->setEnabled(true)`，复用 Falcor 现有 profiler window，不新增新的扩展或窗口状态。

## 验证

- Python 语法检查通过：
  - `scripts\Voxelization_HybridMeshVoxel.py`
  - `scripts\Voxelization_MultiBunny_VoxelOnly.py`
- 定向构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai --parallel 8`
- 运行时 graph IR 验证通过：
  - 用临时 Mogwai 脚本加载 `scripts\Voxelization_MultiBunny_VoxelOnly.py` 后打印 `Graph.print()`，
    当前输出 graph `VoxelizationHybridMeshVoxelVoxelView` 只包含：
    - `VoxelizationPass`
    - `ReadVoxelPass`
    - `RayMarchingDirectAOPass`
    - `ToneMapper`
  - IR 中没有 `MeshGBuffer`、`MeshStyleDirectAOPass`、`HybridBlendMaskPass`、`HybridCompositePass`。

## 后续继续时优先看

- 如果以后还要给其他 launcher 加纯 mesh / 纯 voxel execution mode，先看：
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-06_plan6_execution_mode_split_handoff.md`
- 如果 Profiler 按钮行为需要扩展成 toggle，而不是只打开，优先继续改：
  - `E:\GraduateDesign\Falcor_Cp\Source\Mogwai\MogwaiSettings.cpp`
  - 不要复制 `SampleApp` 的 profiler window 实现。
