# Hybrid Script Launch Defaults Handoff

## 模块职责

统一 hybrid/mainline Mogwai 脚本的启动默认值，保证它们在被独立运行或被 profiling 脚本 `exec()` 间接加载时，都能稳定找到仓库 `resource` cache，并且默认不打开 profiler，避免干扰截图和视觉验证。

## 本轮落地

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - repo 根目录解析不再单纯依赖 `__file__`，会优先检查显式环境变量、脚本路径和当前工作区里的 `resource/scripts` 标记目录。
  - `HYBRID_OPEN_PROFILER` 默认值改为关闭，需要 profiling 时再显式传 `1`。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
  - 同步补了稳态 repo 根目录解析，避免 indirect `exec()` 时 cache 路径漂移。
  - 新增 `DIRECTAO_OPEN_PROFILER`，默认关闭 profiler，必要时显式开启。

## 下一个 AI 优先看

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-07_hybrid_script_launch_defaults.md`
