# Plan4 Phase0 Voxel Baseline

## 目标

冻结当前 Stage4 voxel 主线的对齐基线，给 plan4 后续 mesh 对齐提供可重复的 Mogwai 参考视角、参数记录和窗口截图。

## 当前冻结基线

- 场景：`E:\GraduateDesign\Falcor_Cp\media\Arcade\Arcade.pyscene`
- 脚本：`E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- backend：`CPU`
- 输出模式：`Combined` (`DIRECTAO_DRAW_MODE=0`)
- UI：隐藏 (`DIRECTAO_HIDE_UI=1`)
- capture 分辨率：`1600x900`
- voxel cache：`E:\GraduateDesign\Falcor_Cp\resource\Arcade_(512, 342, 512)_256.bin_CPU`
- ToneMapper：`autoExposure=False`，`exposureCompensation=0.0`

## AO 参数记录

- `DIRECTAO_AO_ENABLED=1`
- `DIRECTAO_AO_STRENGTH=0.55`
- `DIRECTAO_AO_RADIUS=6.0`
- `DIRECTAO_AO_STEP_COUNT=3`
- `DIRECTAO_AO_DIRECTION_SET=6`
- `DIRECTAO_AO_CONTACT_STRENGTH=0.75`
- `DIRECTAO_AO_USE_STABLE_ROTATION=1`

## 参考视角

| 视角 | 环境变量 | position | target | up | focalLength | Mogwai 窗口截图 |
| --- | --- | --- | --- | --- | --- | --- |
| Near | `DIRECTAO_REFERENCE_VIEW=near` | `(-0.811894, 1.575547, 1.825012)` | `(-0.370011, 1.218823, 1.001915)` | `(-0.376237, 0.634521, 0.675103)` | `21.0` | `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_near.png` |
| Mid | `DIRECTAO_REFERENCE_VIEW=mid` | `(-1.143306, 1.843090, 2.442334)` | `(-0.701423, 1.486366, 1.619238)` | `(-0.376237, 0.634521, 0.675103)` | `21.0` | `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_mid.png` |
| Far | `DIRECTAO_REFERENCE_VIEW=far` | `(-1.585189, 2.199814, 3.265431)` | `(-1.143306, 1.843090, 2.442334)` | `(-0.376237, 0.634521, 0.675103)` | `21.0` | `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_far.png` |

## 复现方式

先设置这些环境变量：

```powershell
$env:DIRECTAO_SCENE_PATH='E:\GraduateDesign\Falcor_Cp\media\Arcade\Arcade.pyscene'
$env:DIRECTAO_REFERENCE_VIEW='near' # near / mid / far
$env:DIRECTAO_HIDE_UI='1'
$env:DIRECTAO_FRAMEBUFFER_WIDTH='1600'
$env:DIRECTAO_FRAMEBUFFER_HEIGHT='900'
```

再启动：

```powershell
E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py --scene E:\GraduateDesign\Falcor_Cp\media\Arcade\Arcade.pyscene
```

窗口截图沿用窗口级抓图脚本：

```powershell
powershell -ExecutionPolicy Bypass -File C:/Users/42450/.codex/skills/window-render-capture/scripts/capture_window.ps1 -WindowHandle <handle> -Path E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase0\arcade_near.png
```

## 说明

- Phase0 只冻结 voxel 基线和参考视角，不引入任何 mesh / hybrid pass。
- `far` 机位只做保守后拉，避免把相机拉到房间外侧；阶段0的目标是建立稳定对齐参考，不是追求最完美构图。
