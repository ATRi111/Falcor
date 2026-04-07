# 2026-04-07 MultiBunny Mesh Voxel Shading Gap

- `MultiBunny` 在 hybrid 图里切 `MeshOnly` / `VoxelOnly` 时，兔子颜色差很多的根因不在 `HybridCompositePass`；这个 pass 只是直接回放 `meshColor` 或 `voxelColor`，所以真正的差异来自两条源图各自的着色模型。
- `MeshStyleDirectAOPass` 用的是 GBuffer 原始 `diffuseOpacity/specRough + mesh normal`，而 `RayMarchingDirectAOPass` 会先做 `coverage`、再在 `PrimitiveBSDF::eval()` 里乘 `calcInternalVisibility(l)`，并且 voxel BRDF 只从 4 个法线 lobe 里恢复；如果不关 `HYBRID_VOXEL_CHECK_COVERAGE/HYBRID_VOXEL_CHECK_VISIBILITY` 或不对齐 voxel shading model，`VoxelOnly` 天生就会比 `MeshOnly` 更暗、更斑驳。
