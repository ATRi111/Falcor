# 2026-04-08 DirectAO Visibility/Coverage Defaults

- 调整 `RayMarchingDirectAOPass` 的 `checkVisibility` / `checkCoverage` 默认值时，不能只改 C++ 构造函数；`RayMarchingDirectAO.ps.slang` 的 fallback 宏默认值也要同步，否则 Falcor 预热编译和运行时 define 会出现默认语义不一致。
- 主线 `Voxelization_MainlineDirectAO.py` 和 hybrid `Voxelization_HybridMeshVoxel.py` 都会显式传这两个属性；如果脚本里的 `env_bool(..., True)` 不同步改掉，日常入口仍会覆盖 pass 默认值，现象是“源码默认已关闭，但脚本启动后还是默认开启”。
