# Plan Docs Cleanup Handoff

## 模块职责

本模块负责收拢当前规划文档入口：`plan3.md` 只保留 Stage4 之后的 optional AO 优化，`plan4.md` 单独负责 mesh + voxel 混合渲染设计，`ai_doc_navigation.txt` 只保留当前有效入口。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\ai_doc_navigation.txt`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan_docs_cleanup.md`

## 后续 Agent 应优先查看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_cleanup_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\VBuffer\VBufferRT.cpp`

## 关键结论

- 当前可验收基线仍停在 Stage4 的 voxel 主线，`plan3.md` 不再驱动新的主线必做任务。
- 如果还要继续当前 voxel AO，只按 `plan3.md` 里的 optional stage 推进。
- 如果要做近景 mesh、远景 voxel、中景 blend 的下一阶段方案，只按 `plan4.md` 推进。
- 这次只做了 planning / docs 整理，没有开始实现 mesh 渲染代码。
