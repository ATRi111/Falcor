# 2026-04-07 Highres Voxelization Stall And Crash

- 高分辨率体素化卡很久的主因不是单一 pass，而是 `voxelResolution` 让 `voxelCount/totalVoxelCount` 近似立方增长，同时 `AnalyzePolygon` 又会对每个实体体素做 `13 * sampleFrequency` 级别的估计；分辨率和 sample frequency 一起升时，生成时间会急剧放大。
- 当前 CPU 体素化在 render thread 上同步执行 `clipAll()`，GPU 体素化也会在主流程里 `submit(true)` 并把整块 `vBuffer/polygonCount` 回读到 CPU；异步只会改善 UI 卡死感，不能解决高分辨率下的内存暴涨或 GPU timeout。
- GPU 路径用 `solidRate` 预估 `gBuffer/polygonCountBuffer` 容量，但 `SampleMesh.cs.slang` 分配新 offset 时没有检查是否超过 `maxSolidVoxelCount`；高分辨率或高占用场景下可能直接写越界并触发驱动重置/进程崩溃。
- 2026-04-07 已在 `VoxelizationPass.cpp` 加入生成前安全预估和失败态，在 `SampleMesh.cs.slang` / `VoxelizationPass_GPU.cpp` 加入 `maxSolidVoxelCount` overflow guard；超阈值时现在会中止并打印原因，而不是继续卡死或越界崩溃。
- 2026-04-07 新增 `highMemoryMode`：默认 dense voxel 安全阈值仍是 `64M` voxels，但勾选高内存模式后会放宽到 `128M` voxels；这只放宽“是否允许开跑”，不代表后续 CPU clip / AnalyzePolygon 一定快。
