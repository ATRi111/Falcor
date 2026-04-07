# MultiMultiBunny Scene Handoff

## 模块职责

新增一个独立的 `MultiMultiBunny.pyscene`，让 bunny 阵列相对当前 `MultiBunny` 再提高到 `2x` 实例密度，同时把单兔 scale 适当缩小，便于做更高密度的 mesh / voxel 对比。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Scene\MultiMultiBunny.pyscene`
  - 复用当前 MultiBunny 的材质、地板、相机和灯光。
  - 以当前 `MultiBunny` 作为 baseline：
    - `base_grid_rows = 6`
    - `base_grid_cols = 6`
    - `base_spacing = 0.599635089033322`
    - `base_bunny_scale = 2.4298938248409123`
  - 目标密度：
    - `target_density_multiplier = 2.0`
  - 当前新布局：
    - `grid_rows = 8`
    - `grid_cols = 8`
    - `spacing ≈ 0.403815`
    - `bunny_scale ≈ 1.636376`

## 当前边界

- 这次只新增 scene 文件，没有修改任何现有 launcher、route script 或 cache 前缀。
- 所以默认的：
  - `run_HybridMeshVoxel.bat`
  - `run_MultiBunny_Voxel.bat`
  - `run_VoxelBunny_Blend.bat`
  仍然指向 `Scene\MultiBunny.pyscene`，不会自动切到新场景。

## 验证

- `E:\GraduateDesign\Falcor_Cp\Scene\MultiMultiBunny.pyscene`
  - 已通过 Python 语法检查。

## 后续优先看

- 如果后面要给 `MultiMultiBunny` 配独立 launcher / route script / cache，先看：
  - `E:\GraduateDesign\Falcor_Cp\Scene\MultiMultiBunny.pyscene`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
