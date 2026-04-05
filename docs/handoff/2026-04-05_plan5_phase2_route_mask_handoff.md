# Plan5 Phase2 Route Mask Handoff

## 模块职责

本阶段把 plan5 的 phase2 目标落到当前 hybrid graph：在不重构 mesh 前端的前提下，把 `MeshGBuffer.vbuffer` 接进 route 读取链路，让 `HybridBlendMaskPass`、`HybridCompositePass`、`HybridMeshDebugPass` 都能按 scene instance route 区分 `MeshOnly / VoxelOnly / Blend`，并用 `Arcade` 的参考对象验证 route-aware mask 已经替代纯距离带语义。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5_phase2_capture.py`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_route_debug.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_mesh_route_debug.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_blend_mask.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_composite.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_route_debug_chair_meshonly.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_blend_mask_chair_meshonly.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\arcade_near_composite_chair_meshonly.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\mainline_directao_arcade_near.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_phase2_route_mask.md`

## 关键实现

- `HybridBlendMaskPass` 新增 `vbuffer` 输入，并在 shader 里通过 `HitInfo -> instanceID -> gScene.getGeometryInstanceRenderRoute()` 先判 route：
  - `MeshOnly` 直接输出 `meshWeight = 1`
  - `VoxelOnly` 直接输出 `meshWeight = 0`
  - `Blend` 才继续沿用当前 world-space 距离带
- `HybridCompositePass` 现在同样读取 `vbuffer` 和 `gScene`，新增 `RouteDebug` 查看模式，并把 `BlendMask` 调试图升级成 route-aware 可视化：
  - `MeshOnly` = orange
  - `VoxelOnly` = blue
  - `Blend` = green with distance band
- `HybridMeshDebugPass` 也补了 `RouteDebug`，用同一套 `vbuffer + gScene` 读 route，便于确认 mesh 侧和 composite 侧看到的是同一份 scene instance route。
- `scripts\Voxelization_HybridMeshVoxel.py` 扩了三类能力：
  - `Arcade` 默认 reference routes：`Arch -> Blend`、`Cabinet -> MeshOnly`、`Chair -> Blend`、`poster -> VoxelOnly`
  - `HYBRID_ROUTE_OVERRIDES=Name:Route` 覆写，并在 scene load 后把 route 写回 live scene instance
  - `RouteDebug` 模式和 `MeshGBuffer.vbuffer` 的完整 graph 接线
- `.FORAGENT\plan5_phase2_capture.py` 提供了 phase2 的固定 capture 入口，便于按 basename 批量留图。
- 当前 `Arcade` 街机柜“退远后仍始终是 mesh”是预期行为，不是 blend mask 失效：默认 route 表把 `Cabinet` 写成了 `MeshOnly`，而 `HybridBlendMaskPass` 对 `MeshOnly` 会直接返回 `meshWeight = 1`；只有 `Blend` 对象才会进入距离带。

## 验证结论

- 本轮补完的是 phase2 的截图验收，核对的产物都在 `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\`。
- 默认 `RouteDebug` 和 `Mesh RouteDebug` 结果一致：
  - `Cabinet` 为橙色 `MeshOnly`
  - `poster` 为蓝色 `VoxelOnly`
  - 房间主体为绿色 `Blend`
  说明 `HybridMeshDebugPass` 和 `HybridCompositePass` 看到的是同一份 per-instance route。
- 默认 `BlendMask` 符合 route-aware 语义：
  - `Cabinet` 保持橙色常量，不再进入距离带 lerp
  - `poster` 保持蓝色常量，对应 `meshWeight = 0`
  - 椅子、墙面、地面仍是绿色距离带，对应 `Blend`
- 因此如果观察到“街机远景不切换，但地板/椅子会切换或 blend”，应先检查 route 配置，而不是先怀疑距离带参数；当前默认配置里这正是设计行为。
- `HYBRID_ROUTE_OVERRIDES=Chair:MeshOnly` 的三张对照图验证了 override 行为：
  - `arcade_near_route_debug_chair_meshonly.png` 里两把椅子都从绿色切成橙色
  - `arcade_near_blend_mask_chair_meshonly.png` 里两把椅子都从绿色渐变切成橙色常量
  - `arcade_near_composite_chair_meshonly.png` 中椅子保持纯 mesh 着色，不再继续走默认 blend mask
- 主线 smoke 正常：
  - `mainline_directao_arcade_near.png` 说明 scene route / hybrid pass 改动没有打坏 `Voxelization_MainlineDirectAO.py`
- 相关 capture log 没看到 scene 路径失败或运行时异常，只有已有的 shader warning 和 `Cabinet` emissive UV quantization warning。

## 后续 Agent 应优先查看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_phase2_route_mask.md`

## 下一步注意点

- phase2 只把 route correctness 和 mask 语义跑通了，`VoxelOnly` 仍然会支付 mesh 正式链成本、`MeshOnly` 也还没有从 voxel 正式路径里剔除；真正去掉双路径成本仍属于 plan5 的后续阶段。
- phase3 如果开始补 voxel depth / normal / confidence / routeID，优先保留这轮的 `RouteDebug`、`BlendMask` 和 override capture 口，不要把正确性回归又退回成只看 final composite。
