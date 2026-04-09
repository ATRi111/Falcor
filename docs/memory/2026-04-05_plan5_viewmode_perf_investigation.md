# 2026-04-05 Plan5 ViewMode Perf Investigation

- `HybridCompositePass.viewMode` 里的 `MeshOnly` / `VoxelOnly` / `RouteDebug` 是显示/调试视图，不是全局执行模式；当前 hybrid graph 仍会固定创建并连接 mesh 与 voxel 两条正式链，切 view mode 不会自动裁剪 pass。
- 2026-04-05 的 Arcade hybrid 默认实例 route 已全部回退到 `Blend`，所以即使 `Composite` 视图启用了 Phase5 selective execution，`GBufferRaster(Blend|MeshOnly)` 和 `RayMarchingDirectAOPass(Blend|VoxelOnly)` 仍会各自覆盖整景，FPS 基本不会因切 `Composite/MeshOnly/VoxelOnly` 而变化。
- Phase5 的 debug full-source 修复还会让 `MeshOnly` / `VoxelOnly` / `BlendMask` / `RouteDebug` / `ObjectMismatch` / `DepthMismatch` 临时放宽 route mask；这些视图本来就不该被当成性能模式验收。
