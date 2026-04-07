# MultiBunny Launcher Cache Sync Handoff

## 模块职责

把三份 MultiBunny 根目录 launcher 的显式 cache / scene hint 配置对齐到当前 sparse-layout + lerp-normal 基线，避免 bat 层继续覆盖脚本默认值或提示旧 cache 文件名。

## 当前状态

- `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
  - `VOXEL_CACHE` 改为 `resource\MultiBunnySparseLerp_(128, 16, 128)_128.bin_CPU`。
  - `HYBRID_SCENE_HINT` 改为 `MultiBunnySparseLerp`，并显式补上 `HYBRID_CPU_SCENE_NAME/HYBRID_VOXEL_CACHE_FILE`，避免 launcher 把脚本重新拉回旧 `MultiBunny` 命名。
- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
- `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
  - warning 用的 `VOXEL_CACHE` 改为当前 sparse-layout cache。
  - 启动前显式设置 `HYBRID_CPU_SCENE_NAME/HYBRID_VOXEL_CACHE_FILE`，让 bat 提示与脚本实际读写目标保持一致。

## 验证

- 静态检查通过：
  - 三份 bat 里所有显式 cache 路径、scene hint 已与 `scripts\Voxelization_MultiBunny_VoxelOnly.py`
    `scripts\Voxelization_MultiBunny_VoxelRoute.py`
    `scripts\Voxelization_VoxelBunny_Blend.py`
    当前默认值对齐。
- 本轮没有再单独重跑 Mogwai；launcher 变更边界只涉及环境变量和 warning 文案，不涉及 shader、graph 或 C++ pass 行为。

## 后续继续时优先看

- 如果后面继续改 `MultiBunny` cache 名或 scene hint，先同时检查：
  - `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
