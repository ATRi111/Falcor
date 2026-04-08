# DirectAO Visibility/Coverage Defaults Handoff

## 模块职责

统一 `RayMarchingDirectAOPass`、shader fallback 宏和主线/Hybrid 脚本入口的 `CheckVisibility`、`CheckCoverage` 默认语义，避免“源码默认”和“脚本默认”不一致。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`

## 继续工作时优先看

- 若用户问三个开关各自控制什么，先看 `Shading.slang` 里 `calcCoverage()`、`updateCoverage()`、`calcInternalVisibility()`，再看 `RayMarchingTraversal.slang` 里的 `calcLightVisibility()` 和 `rayMarching()/rayMarchingConservative()`。
- 若脚本启动后的默认表现和 UI 不一致，优先排查两个 Python 脚本是否又显式覆写了 `checkVisibility` / `checkCoverage`。
