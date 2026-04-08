# Voxel Hit Face Normal Handoff

## 模块职责

在 `RayMarchingDirectAO` 里把“BSDF 主 lobe 法线”和“主射线实际命中面法线”拆开，优先用 ellipsoid hit face normal 驱动调试输出与 ray-bias，降低 voxel silhouette 黑边。

## 本次改动

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - 新增 `orientNormal()`、`tryEvalEllipsoidFaceNormal()`、`resolveHitFaceNormal()`，用 `pBuffer[offset].B`、`ellipsoid.center` 和 `hit.cell` 恢复主射线命中的 ellipsoid 面法线。
  - `NormalDebug` 和 `voxelNormal` 现在优先输出 hit face normal；如果当前 hit 来自 conservative fallback、不是有效 ellipsoid clip 点，则退回 `bsdf.surface.getMainNormal(viewDir)`。
  - direct-light shadow visibility 和 AO probe 的起点偏移都改为使用 hit face normal；AO 的采样 basis 仍保留 `bsdfMainNormal`，避免直接改动当前 voxel BRDF 的聚合外观。

## 根因结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
  - `SurfaceBRDF::getMainNormal(direction)` 只会从 4 个聚合法线 lobe 中挑最大权重 lobe，再按给定方向翻面；它不知道主射线实际打在 ellipsoid 的哪一侧，所以不能直接当作 first-hit face normal。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
  - 主射线在 ellipsoid refine 成功时已经把 clip 命中点写进 `hit.cell`，旧的 `RayMarchingDirectAO` 只是没有消费这条更精确的几何信息。

## 验证

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization Mogwai`
- 窗口级 smoke 通过：
  - 启动 `scripts\Voxelization_MultiBunny_VoxelOnly.py` + `Scene\MultiMultiBunny.pyscene` 后可正常打开 Mogwai 并抓图。
  - 验证图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_runtime_normal_smoke.png`

## 继续排查时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Math\Ellipsoid.slang`

## 后续注意

- 这次只把 debug/ray-bias 法线切到 hit face normal，没有改 `bsdf.eval()` 的 4-lobe 聚合 BRDF；如果后面 silhouette 暗边仍有残留，下一步优先看 AO 采样 basis 是否也需要从 `bsdfMainNormal` 向 hit face normal 收敛，而不是先回去改 cache 或 composite。
