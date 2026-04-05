# Plan5 Route Hybrid Handoff

## 模块职责

本模块负责把两份 deep research 报告和当前仓库现状收敛成新的主实施计划 `plan5.md`，并同步清理会误导后续 Agent 的过渡文档入口。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\ai_doc_navigation.txt`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_route_hybrid.md`

## 关键结论

- `plan5.md` 现在是对象级 hybrid 路由的唯一主计划；`plan4.md` 只保留当前 prototype 的历史阶段背景，原本剩余的最后一个阶段不再单独实施。
- 新主线选择的是“`per-instance` route + voxel identity 扩展 + selective execution”，而不是直接把当前仓库整体切成 VBuffer-first 或双 Scene 迁移架构。
- 第一版继续沿用当前 `GBufferRaster + MeshStyleDirectAOPass` mesh 正式链，只要求补 route/identity/contract；是否进一步切到 `VBufferRaster / VBufferRT` 或 `cluster/HLOD voxel proxy`，要等 Phase5 profiling 之后再决定。
- 这次文档清理的原则是：保留能帮助后续 Agent 直接进入当前代码状态的 handoff，删除只承担过渡入口职责、现在已经被 `plan5.md` 吸收的 handoff。

## 已删除的过渡 handoff

- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-05_plan_docs_cleanup_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-05_handoff_cleanup_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-05_future_hybrid_renderer_vision_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-05_plan4_object_route_analysis_handoff.md`

## 后续 Agent 应优先查看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\future_hyrbid_renderer_plan.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-05_plan4_phase4_hybrid_blend_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_route_hybrid.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneTypes.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneBuilder.cpp`
