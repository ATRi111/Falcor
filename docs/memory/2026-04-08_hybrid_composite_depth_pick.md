# 2026-04-08 Hybrid Composite Depth Pick

- `Blend`/instant LOD 场景里如果 `VoxelOnly` 物体背后还有 `MeshOnly` 地板，`VoxelOnly` 单独渲染正常但 `Composite` 看起来会像“voxel 没画出来”；触发条件是 `HybridCompositePass.ps.slang` 以前只要 mesh path 有命中就无条件选 mesh，不比较前后深度。
- 规避方式是在 composite 里同时拿 `meshDepth` 和 `voxelDepth` 做前景判定；当 voxel 命中明显比 mesh 更近时必须优先显示 voxel，否则后面的 mesh 地板会把前面的 voxel 物体整片盖掉。
