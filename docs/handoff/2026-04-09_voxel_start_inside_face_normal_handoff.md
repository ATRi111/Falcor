# Voxel Start-Inside Face Normal Handoff

## 模块职责

`RayMarchingDirectAO` 负责恢复 voxel first-hit 的运行时法线，并把它同时用于 `NormalDebug`、direct-light shadow receiver bias 和 AO probe 起点；这一层一旦退回到错误法线，debug 颜色异常和黑色 silhouette 体素会同步出现。

## 本次改动

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - 修改 `tryEvalEllipsoidFaceNormal()`：不再把所有 `implicit != 1` 的命中直接判成失败。
  - 对 ellipsoid 壳内命中先做径向壳面投影 `shellOffset = offset / sqrt(x^T B x)`，再用 `B * shellOffset` 取法线，避免回退到 `bsdfMainNormal`。
  - 仅对“轻微壳外”的点放宽容差，明显偏离 ellipsoid 的点仍回退，继续隔离 conservative fallback / 无效 cell-center。

## 根因结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Math\Ellipsoid.slang`
  - voxel 内保存的是 fitted bounding ellipsoid，不保证严格被 cell 边界裁掉；在 silhouette/grazing 机位下，主射线可能一进当前 cell 就已经位于 ellipsoid 内部。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - 旧版 `tryEvalEllipsoidFaceNormal()` 用 `abs(implicit - 1.0f) <= 0.15` 作为硬条件，壳内命中会直接失败并退回 `bsdfMainNormal`；`NormalDebug` 和 direct shadow bias 共用这条回退路径，所以两种 artifact 会一一对应。

## 验证

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization Mogwai`
- 运行时窗口 smoke：
  - 默认远景 `DirectOnly`：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\2026-04-09_voxel_directonly_runtime_smoke.png`
  - 默认远景 `NormalDebug`：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\2026-04-09_voxel_normaldebug_runtime_smoke.png`
  - 近景机位 `DirectOnly`：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\2026-04-09_voxel_directonly_close_runtime_smoke.png`
  - 近景机位 `NormalDebug`：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\2026-04-09_voxel_normaldebug_close_runtime_smoke.png`

## 继续排查时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Math\Ellipsoid.slang`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\capture_voxel_debug_mode.py`

## 后续注意

- 这轮验证覆盖了之前 close-up 调试用的相机参数：`position=0.0,0.92,1.85`、`target=0.0,0.25,0.10`、`up=0.0,1.0,0.0`、`focalLength=24.0`；如果用户仍能在别的机位看到一对一的黑边/异色，下一步优先加一个临时 debug mask 区分 `implicit < 1`、`implicit ~= 1` 和 fallback 命中，而不是先回去调 AO 或 cache。
