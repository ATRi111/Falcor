# 2026-04-07 MultiBunny Voxel Graph And Profiler Button

- `Voxelization_MultiBunny_VoxelOnly.py` 如果继续复用 hybrid graph，只把 `HYBRID_OUTPUT_MODE=voxelonly` 切到 `VoxelOnly`，Graphs UI 里仍会保留 `MeshGBuffer/HybridCompositePass`；要让 `run_MultiBunny_Voxel.bat` 真正只打开体素链，必须额外引入独立的 pure-voxel graph 分支，而不是只改 composite 输出模式。
- Mogwai 的 Profiler 窗口已经由 `SampleApp` 内建管理，Graphs 面板里不需要重做一套 profiler UI；按钮只要把 `getDevice()->getProfiler()->setEnabled(true)` 打开，就会复用现有 `Profiler` 窗口逻辑。
