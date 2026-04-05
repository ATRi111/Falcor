# 2026-04-05 Plan4 Object Route Analysis

- 当前 `Voxelization_HybridMeshVoxel.py` 在 `HYBRID_OUTPUT_MODE=Composite/MeshOnly/VoxelOnly/BlendMask` 下会同时挂上 mesh 和 voxel 两条正式出图链，`MeshOnly/VoxelOnly` 只是合成查看模式，不会减少非 blend 物体的双路径评估成本。
- 现有 hybrid 没有对象级 `voxel / mesh / blend` 路由源：scene 侧没有 render-route 字段，blend mask 只看 mesh `posW` 距离，voxel 路径也只输出最终 `color`，所以当前既做不到按对象裁路径，也很难做稳定的深度/置信度修正混合。
