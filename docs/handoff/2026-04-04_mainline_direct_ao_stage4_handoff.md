# Mainline DirectAO Stage4 Handoff

## 模块职责

当前 voxel 主线的可验收基线。后续所有 hybrid 变更都要以 `scripts\Voxelization_MainlineDirectAO.py` 仍可稳定运行作为回归底线。

## 当前状态

- `RayMarchingDirectAOPass` 已完成稳定的 `contactAO + macroAO` baseline；`Combined`、`DirectOnly` 和 `AOOnly` 都沿用当前 `ReadVoxelPass` 输入契约。
- legacy `VoxelDirectAO*` 已退役；源码和脚本入口只保留 `RayMarchingDirectAO*` 与 `scripts\Voxelization_MainlineDirectAO.py`。
- 主线脚本已收敛成 `ReadVoxelPass -> RayMarchingDirectAOPass -> ToneMapper`，不要再把 `RenderToViewportPass`、`AccumulatePass` 或旧 pass 名接回验收链路。
- `AOOnly` 需要保留调试曲线映射，稳定 AO 的方向打散只能来自稳定 hash，不能重新引入逐帧随机。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-05_plan4_phase0_voxel_baseline.md`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`

## 验证口径

- 构建基线：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization`
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`
- 画面基线：
  使用 `Arcade` 的 near / mid / far 固定机位做窗口级复核，参考 `docs\development\2026-04-05_plan4_phase0_voxel_baseline.md`。
- 任何跨 scene core、voxel contract 或 hybrid graph 的修改，都要额外 smoke 一次这条主线。

## 继续工作时优先看

- 先看 `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py` 的 graph 链路是否仍然只包含主线需要的 pass。
- 如果要扩 cache 或读写契约，直接看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`，不要依赖已经删除的旧 plan 文档。
- 如果画面回到“AOOnly 近白占位”或重新出现 temporal shimmer，先检查 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 的 AOOnly 映射和稳定方向集。
