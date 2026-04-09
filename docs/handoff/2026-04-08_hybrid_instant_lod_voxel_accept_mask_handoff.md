# Hybrid Instant LOD Voxel Accept Mask Handoff

## 模块职责

- 修正 instant LOD hybrid 图里 `VoxelRoutePreparePass` 的 route accept 一致性，避免 `Blend -> VoxelOnly` 后出现视角相关的 voxel 空窗。

## 关键结论

- `scripts\Voxelization_HybridMeshVoxel.py` 当前的 `Blend` 语义是整实例瞬切，不是连续权重混合；因此 route resolve 到 `VoxelOnly` 后 mesh 消失属于预期。
- 本轮真正修的是 `Source\RenderPasses\Voxelization\VoxelRoutePrepare.cs.slang`：
  - 之前 low-confidence / invalid-identity voxel 会进入 `resolvedBlockMap`
  - 但同一个 voxel 的 `solidVoxelAcceptedRouteMask` 却被写成 `0`
  - `RayMarchingTraversal.slang` 随后又严格按 `acceptedRouteMask` 过滤，导致 traversal 已进入 block、first hit 却被二次拒绝，表现成机位相关的缺口或整只物体消失
- 现在 low-confidence / invalid dominant ID 会统一返回 `AllRoutes`，让 block-level 与 cell-level 的 route 过滤保持一致。
- `scripts\Voxelization_HybridMeshVoxel.py` 里的 `resolve_lod_route()` 也做了第二处修正：不再用相机到实例球心的三维距离做瞬切，而是优先按相机前向视深减去 bounds radius 判断 `MeshOnly/VoxelOnly`。这样抬高摄像机不会仅因为 `y` 增大就把一批仍然很大的物体过早切到 voxel。
- `scripts\Voxelization_VoxelBunny_Blend.py` 与 `run_VoxelBunny_Blend.bat` 也补了 scene-aware 默认阈值：
  - `MultiBunnyDense1p5Lerp -> 4.375`
  - `MultiMultiBunny -> 5.0`
  当前 `run_VoxelBunny_Blend.bat` 会显式设置 `HYBRID_LOD_SWITCH_DISTANCE=5.0`，避免 launcher 已换新场景、阈值却仍停在旧场景配置。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelRoutePrepare.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
- `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`

## 残余风险

- 这次没有改变 instant LOD 的整实例瞬切策略，所以如果用户觉得“切到 voxel 太早”，应继续调 `HYBRID_LOD_SWITCH_DISTANCE` 或换成屏幕空间阈值，而不是回头查 composite。
- 这次也没有扩 voxel payload/layout；mixed voxel 若 dominant contributor 本身就属于别的实例，仍可能出现“命中了但形态/归属不够对”的残余问题。那类问题需要继续看 `docs/handoff/2026-04-06_plan6_phase5_accepted_route_limit_handoff.md` 里提到的 payload 扩展方向。

## 验证

- `run_VoxelBunny_Blend.bat` shader/runtime smoke 通过，`VoxelRoutePrepare.cs.slang` 与 `HybridCompositePass.ps.slang` 都能在 Mogwai 启动时完成编译，没有新增 shader error。
- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization HybridVoxelMesh Mogwai`
  编译通过。
- `python -m py_compile scripts/Voxelization_HybridMeshVoxel.py`
  脚本语法通过。
- `python -m py_compile scripts/Voxelization_VoxelBunny_Blend.py`
  脚本语法通过。
- 验证日志：
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\instant_lod_smoke_stdout.log`
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\instant_lod_smoke_stdout_second.log`
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\instant_lod_smoke_nogen_stdout.log`
