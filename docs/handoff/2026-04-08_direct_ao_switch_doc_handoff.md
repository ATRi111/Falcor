# DirectAO Switch Doc Handoff

## 模块职责

把 `RayMarchingDirectAOPass` 中 `CheckEllipsoid`、`CheckVisibility`、`CheckCoverage` 的语义、公式和代码落点整理成固定文档，方便后续 AI 或人工排查 shading 差异时直接引用。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-08_raymarching_direct_ao_switches.md`
- `E:\GraduateDesign\Falcor_Cp\docs\development\index.md`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Math\Ellipsoid.slang`

## 继续工作时优先看

- 若用户问“为什么 `VoxelOnly` 比 `MeshOnly` 更暗 / 更斑驳”，先看这份文档里 `CheckCoverage` 和 `CheckVisibility` 两节，再回到 `Shading.slang` 的 `PrimitiveBSDF::eval()`。
- 若用户把 `CheckVisibility` 和 shadow ray visibility 混为一谈，优先对照 `Shading.slang::calcInternalVisibility()` 与 `RayMarchingTraversal.slang::calcLightVisibility()` 的区别。
