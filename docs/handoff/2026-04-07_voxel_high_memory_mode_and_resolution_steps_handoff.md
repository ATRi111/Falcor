# Voxel High Memory Mode And Resolution Steps Handoff

## 模块职责

给 `VoxelizationPass` 增加面向高内存机器的 dense voxel 安全开关，并把 UI 的 `Voxel Resolution` 离散档位在 `256-512` 和 `512-1000` 之间补细，减少只能在 `512` 和 `1000` 之间硬跳的情况。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationProperties.h`
  - 新增 `highMemoryMode` 属性常量。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.h`
  - 基类状态新增 `mHighMemoryMode`。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.cpp`
  - dense voxel safety limit 现在分成两档：
    - 默认：`64M` voxels
    - 高内存模式：`128M` voxels
  - UI 新增 `High Memory Mode` 复选框和 `Dense Voxel Safety Limit` 文本。
  - `Voxel Resolution` 档位新增：`192, 224, 320, 384, 448, 576, 640, 704, 768, 832, 896, 960`。

## 行为说明

- `High Memory Mode` 只放宽 dense voxel guard，不会同步放宽 `3 GiB` 的峰值工作集安全阈值。
- 所以它的含义是“允许更大的 dense index 开跑”，不是“关闭所有保护”。
- 当前默认报错文案会直接提示：
  - 关闭高内存模式时：`Enable High Memory Mode or reduce voxelResolution`
  - 打开高内存模式后：如果仍超限，只会提示继续降低分辨率

## 验证

- `E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\plugins\Voxelization.dll`
  - 已重新编译通过。
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\highmem_off_probe_stdout.log`
  - `voxelResolution=1000` 且 `highMemoryMode=0` 时，已命中：
    - `Enable High Memory Mode or reduce voxelResolution before generating.`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\highmem_on_probe_stdout.log`
  - `voxelResolution=1000` 且 `highMemoryMode=1` 时，不再被 `64M` dense voxel guard 直接拦下，日志已进入：
    - `CPU voxelization queued async clipping task ...`

## 后续优先看

- 如果后面要继续放宽阈值，优先改：
  - `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.cpp`
- 如果后面要把高内存模式也暴露到脚本/bat 默认入口，优先改：
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
