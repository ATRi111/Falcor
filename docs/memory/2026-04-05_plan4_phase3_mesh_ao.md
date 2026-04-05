# 2026-04-05 Plan4 Phase3 Mesh AO

- 把 deterministic direct 从 `HybridMeshDebugPass` 拆到独立 `MeshStyleDirectAOPass` 时，如果忘了同步删掉 debug pass 里旧的 pybind 属性绑定（这次是 `shadowBias`），`HybridVoxelMesh` 会在 C++ 编译阶段直接报成员不存在；split pass 时要连同脚本属性和绑定一起收口。
- mesh AO 不能直接沿用 voxel 主线 `aoRadius=6.0` 的标尺；`GBufferRaster` 走的是 world-space mesh 几何，第一版 AO 需要单独的 mesh world-space 半径（当前默认 `0.18`），否则 `AOOnly` 很容易整屏近白只剩细边，或反过来把 `Combined` 压得过黑。
