# Mainline DirectAO Plan3 Handoff

## 模块职责

本模块负责把主线 `RayMarchingDirectAO*` 在 Stage3 之后的剩余工作重新整理成执行手册，并明确 legacy `VoxelDirectAO*` 的退役顺序。

## 本轮产物

- 新主计划：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
  - 该文件已取代 `plan2.md`，只保留 Stage4 及之后
- 记忆沉淀：`E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-04_mainline_direct_ao_plan3.md`

## 后续 Agent 应优先查看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-04_mainline_direct_ao_stage3.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage3_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

## 关键结论

- Stage4 不应直接跳去 `voxelOcclusion` 预计算；更稳的顺序是“稳定 AO baseline -> `aoOccupancy` mip -> 层级 AO -> 可选方向性预计算/环境项”。
- `aoOccupancy` 应先做成可采样的 float/unorm 3D mip 结构，而不是只做整数 bitmask；否则 Stage6 的层级 AO 采样路径会很别扭。
- 更早的 `VoxelDirectAO*` 路线现在只剩历史参考价值，已经单独列为 Stage8 清理任务；真正执行清理前，不要再往 legacy pass 里补功能。

