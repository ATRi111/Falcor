# Voxel BlackBlock Attempts And Rollback Handoff

## 模块职责

这轮工作围绕 `RayMarchingDirectAO` 的 voxel 直射着色黑块做排查，并在确认没有稳定修复后，把源码回退到修复前基线，只保留排查文档和已知结论。

## 已尝试并排除

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - `FaceNormalMask` 说明黑块和 `start-inside` / `fallback` 法线分类不对位，hit-face-normal 不是主因。
  - `LightVisibilityMask` 说明黑块和 `calcSceneLightVisibility()` 的 `blockedOther` / `blockedSameObject` / `silhouetteRescued` 也不对位，scene visibility 不是主因。
  - `UnshadowedDirect` 在绕过 visibility 后仍保留黑块，进一步排除 AO / shadow ray 路径。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
  - 试过 `evalSmoothed()`、平均 lobe normal、faceNormal 混合，以及按 `h` 或 `±n` 选半球 frame；用户机位下边缘黑块仍残留，没有形成可接受修复。

## 当前保留结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Voxel\ABSDF.slang`
  - `NormalIndex()` 目前只把法线压进 `±X / ±Z` 四个桶，`LOBE_COUNT=4`；这是当前最可疑的结构性原因，但本轮没有继续动缓存布局去验证。
- 远程分支里保留了一份调试快照：
  - branch: `codex/plan5-object-route`
  - commit: `2fed3643` (`debug voxel direct shading artifacts`)
  - 需要复盘具体 debug mode 时可以从这份快照看，而不是重新手搓。

## 本次回退

- 回退目标 commit：
  - `7db5f9ada617a00fa39ff636ab36abaff9af4c8d`
- 仅回退源码文件：
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- 文档保留：
  - `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-09_voxel_start_inside_face_normal.md`
  - `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-09_voxel_start_inside_face_normal_handoff.md`
  - `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-09_voxel_brdf_lobe_quantization.md`
  - `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-09_voxel_brdf_lobe_quantization_handoff.md`

## 后续继续时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Voxel\ABSDF.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-09_voxel_blackblock_attempts_and_rollback.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-09_voxel_brdf_lobe_quantization_handoff.md`
