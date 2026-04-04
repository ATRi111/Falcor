# Mainline DirectAO Stage4 Cleanup Handoff

## 模块职责

本模块负责退役已经不再运行的 `VoxelDirectAO*` legacy 路线，并把主线 `Voxelization_MainlineDirectAO.py` 收敛成只保留当前验收需要的 graph 链路。

## 实现入口

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

## 当前状态

- `VoxelDirectAOPass`、`VoxelDirectAO.ps.slang` 和 `scripts\Voxelization_DirectAO.py` 已从源码入口移除，后续不要再按 legacy pass 名称搜索实现入口。
- `Voxelization_MainlineDirectAO.py` 已去掉 `RenderToViewportPass` 和 `AccumulatePass`，当前主线图直接把 `RayMarchingDirectAOPass.color` 送进 `ToneMapper`。

## 继续工作时优先看

- 如果主线 DirectAO 行为不对，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp` 和 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`，不要回头找 `VoxelDirectAO*`。
- 如果脚本启动失败，先看 `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py` 的 graph 边是否仍然只连接 `ReadVoxelPass -> RayMarchingDirectAOPass -> ToneMapper`。
