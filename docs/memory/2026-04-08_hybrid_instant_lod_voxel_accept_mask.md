# 2026-04-08 Hybrid Instant LOD Voxel Accept Mask

- `Blend` 物体在 instant LOD 脚本里会被整实例瞬切成 `MeshOnly/VoxelOnly`，所以一旦某实例解析到 `VoxelOnly`，mesh 消失是当前设计语义，不是 composite 丢图。
- 真正导致“有时往下压机位才看到、有时直接看不到”的回归在 `VoxelRoutePrepare.cs.slang`：低置信度或无 dominant ID 的 solid voxel 之前会保留到 `resolvedBlockMap`，却把 `acceptedRouteMask` 写成 `0`，触发 block 被遍历但 cell hit 再被拒绝；修复方式是这类 voxel 统一返回 `AllRoutes`，保持 block/cell 过滤一致。
- 即使 accept-mask 修完，`resolve_lod_route()` 如果继续用相机到实例球心的三维距离做瞬切，也会把相机高度直接算进 LoD；在俯视或抬高机位时，一批屏幕上仍然很大的实例会被过早判成 `VoxelOnly`。规避方式是改按相机前向视深做切换，而不是直接用欧氏距离。
- `run_VoxelBunny_Blend.bat` 切到 `MultiMultiBunny` 后，如果还沿用 `Voxelization_VoxelBunny_Blend.py` 里给旧 `MultiBunnyDense1p5Lerp` 调的 `HYBRID_LOD_SWITCH_DISTANCE=4.375`，默认机位会只剩最近 3 排 mesh；需要按 scene hint 给 `MultiMultiBunny` 单独提高默认阈值，本轮先收在 `5.0`。
