# MultiBunny Sparse Layout Handoff

## 模块职责

把 `MultiBunny` 从原来的高密度 10x10 阵列调整为横竖密度都减半、但单兔整体 scale 翻倍的新布局，并同步切换 voxel/blend 入口的 cache 前缀，避免继续读到旧布局缓存。

## 当前状态

- `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
  - Bunny 阵列从 `10x10` 改为 `5x5`。
  - 单兔 `scaling` 从 `1.55` 提到 `3.10`。
  - `spacing` 改为 `0.765`，保持新阵列大致沿用旧布局的总铺开范围，而不是缩成中间一小团。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
  - 统一切到新的 sparse-layout cache 前缀：
    - `HYBRID_SCENE_HINT=MultiBunnySparseLerp`
    - `HYBRID_CPU_SCENE_NAME=MultiBunnySparseLerp`
    - `HYBRID_VOXEL_CACHE_FILE=resource\\MultiBunnySparseLerp_(128, 16, 128)_128.bin_CPU`
  - `HYBRID_CPU_LERP_NORMAL=1` 保持不变，继续沿用之前修掉地面假阴影的基线。

## 验证

- Python 语法检查通过：
  - `Scene\MultiBunny.pyscene`
  - `scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `scripts\Voxelization_VoxelBunny_Blend.py`
- `VoxelOnly` 首启 smoke 通过：
  - 新 cache `E:\GraduateDesign\Falcor_Cp\resource\MultiBunnySparseLerp_(128, 16, 128)_128.bin_CPU` 已成功生成。
  - 45 秒运行窗口内没有新增 stderr 异常。
- 窗口级确认：
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multibunny_sparse_layout.png`
  - 结果显示为更稀疏的 5x5 大兔子阵列，符合本轮布局目标。

## 后续继续时优先看

- 如果后面继续改 MultiBunny 的布局、scale 或相机，先看 `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`。
- 如果又改 scene bounds，记得同步检查三份 voxel/blend 脚本里的显式 cache 文件名，尤其是 voxel count 中间那一维是否还保持 `16`。
- `MeshRoute` 脚本不依赖 voxel cache，这轮没有改它。
