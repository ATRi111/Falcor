# MultiBunny Density 1p5 Layout Handoff

## 模块职责

把 `MultiBunny` 从当前 `5x5` sparse layout 提到约 `1.5x` 的实例密度，同时把单兔 scale 同步缩小，并把所有依赖显式 voxel cache 的 MultiBunny 入口切到新的 cache 前缀，避免继续读旧布局缓存。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
  - 阵列从 `5x5` 改为 `6x6`。
  - 用 `target_density_multiplier = 1.5` 和 `layout_scale` 计算新布局。
  - 当前实际参数约为：
    - `spacing = 0.599635`
    - `bunny_scale = 2.429894`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
  - 默认 `HYBRID_SCENE_HINT` 改为 `MultiBunnyDense1p5Lerp`，方便 standalone mesh route 和当前布局保持一致。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
  - 统一改到新的 cache 前缀：
    - `HYBRID_SCENE_HINT=MultiBunnyDense1p5Lerp`
    - `HYBRID_CPU_SCENE_NAME=MultiBunnyDense1p5Lerp`
    - `HYBRID_VOXEL_CACHE_FILE=resource\\MultiBunnyDense1p5Lerp_(128, 16, 128)_128.bin_CPU`
- `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
- `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
  - 与脚本保持同一份 `MultiBunnyDense1p5Lerp` 显式 cache 路径和 scene hint。

## 验证

- 语法检查通过：
  - `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multibunny_density_1p5_stdout.log`
  - 启动日志已切到新 cache 前缀：
    - `resource\\MultiBunnyDense1p5Lerp_(128, 16, 128)_128.bin_CPU`
  - 同一轮日志还显示 CPU voxelization 已开始新布局生成：
    - `queued async clipping task for 74600 triangles across 37 instances`

## 后续优先看

- 如果后面继续改 MultiBunny 阵列密度、scale 或 spacing，先看：
  - `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
- 如果后面继续改 MultiBunny 的 voxel cache 命名或分辨率，先同步检查：
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
  - `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
