# 2026-04-07 MultiBunny Mesh Perf Reason

- `run_HybridMeshVoxel.bat mesh` 不是 hybrid graph 里把 `HybridCompositePass.viewMode` 切到 `MeshOnly`，而是经 `Voxelization_MultiBunny_MeshRoute.py` 把 `HYBRID_OUTPUT_MODE=meshview` 固定到独立 mesh graph；把两者混为一谈会直接误判性能结论。
- `MultiBunny` 当前只有 `5x5` 只 Bunny，共约 `25 * 74,598 = 1.86M` triangles，mesh 路径又是 `GBufferRaster + MeshStyleDirectAOPass` 的延迟着色结构，成本主要按可见像素增长；若要在不改光照模型的前提下拉开与 voxel 的对比，优先提高分辨率或实例密度，forward 仅适合作为额外 reference 模式。
