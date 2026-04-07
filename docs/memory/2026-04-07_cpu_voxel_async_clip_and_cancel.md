# 2026-04-07 CPU Voxel Async Clip And Cancel

- `VoxelizationPass_CPU` 现在只把 CPU 裁剪阶段异步化：render thread 仍负责 `LoadMesh`、GPU->CPU 回读、GPU buffer 上传和后续 `AnalyzePolygon`；因此它解决的是 Mogwai 长时间无响应，不是总生成时间魔法下降。
- 可取消只覆盖后台 `clipAll()` 线程，依赖 `PolygonGenerator` 的 triangle-loop 轮询取消标志；如果后续还要扩展到 GPU backend，必须另做独立状态机，不能复用这套 CPU cancel 语义。
