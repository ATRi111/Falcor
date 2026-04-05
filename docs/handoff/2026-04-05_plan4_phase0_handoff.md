# Plan4 Phase0 Handoff

## 模块职责

本模块负责冻结当前 Stage4 voxel 主线的参考基线，为后续 plan4 的 mesh direct、mesh AO 和 hybrid blend 对齐提供固定机位、参数记录和 Mogwai 窗口截图。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-05_plan4_phase0_voxel_baseline.md`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_near.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_mid.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_far.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase0_baseline.md`

## 关键实现

- `Voxelization_MainlineDirectAO.py` 新增了 `DIRECTAO_REFERENCE_VIEW=near/mid/far`，并支持 `DIRECTAO_CAMERA_POSITION / TARGET / UP / FOCAL_LENGTH` 显式覆写，便于后续 Agent 精确复现场景。
- 相机落位通过 `m.sceneUpdateCallback` 一次性应用，规避了 `--scene` 绑定晚于脚本执行时机的问题。
- 参考截图统一要求 `DIRECTAO_HIDE_UI=1` 和 `1600x900` 输出，避免后续对比时混入 UI 面板或窗口尺寸差异。

## 继续工作时优先看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-05_plan4_phase0_voxel_baseline.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_handoff.md`

## 关键结论

- Phase0 已完成，当前仓库里已经有近景、中景、远景三组可复现参考机位。
- 本轮没有开始 mesh 渲染或 hybrid pass 实现；后续如果进入 plan4 Phase1，应先沿用这三组机位做 mesh-only debug 对比。
