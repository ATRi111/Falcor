# 2026-04-05 Plan5 Phase5 MeshOnly Debug Fix

- Phase5 把 hybrid 正式链的 `GBufferRaster`/`RayMarchingDirectAOPass` 按 route mask 过滤后，`HybridCompositePass` 的 `MeshOnly`/`VoxelOnly` 及相关 debug 视图会直接读到被裁掉的正式源图，典型现象就是 `Arcade` 里 `poster -> VoxelOnly` 在 `MeshOnly` 下变成纯黑块。
- 修复方式是让 `HybridCompositePass` 按当前 view mode 往 graph dictionary 写 `requireFullMeshSource/requireFullVoxelSource`，只在这些调试视图里临时放宽 route mask；`Composite` 视图继续保留 Phase5 selective execution。
- `Arcade` hybrid 结果如果整体比 PathTracer 更暗，先排查是不是误走了旧的 `media/Arcade/Arcade.pyscene` 变体；2026-04-05 已删除这份重复脚本，并把 hybrid 默认入口统一到 `Scene/Arcade/Arcade.pyscene`。
- `scripts/Voxelization_HybridMeshVoxel.py` 里曾经放过 `Cabinet -> MeshOnly` / `poster -> VoxelOnly` 的 Arcade 参考 route 覆写；2026-04-05 起这张表已清空，当前默认行为是所有实例回退到 builder 默认 `Blend`。
