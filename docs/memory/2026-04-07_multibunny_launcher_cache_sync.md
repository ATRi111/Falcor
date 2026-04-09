# 2026-04-07 MultiBunny Launcher Cache Sync

- `run_HybridMeshVoxel.bat`、`run_MultiBunny_Voxel.bat`、`run_VoxelBunny_Blend.bat` 如果不和脚本里的 `HYBRID_SCENE_HINT/HYBRID_CPU_SCENE_NAME/HYBRID_VOXEL_CACHE_FILE` 同步，首启提示会指向旧 cache，`run_HybridMeshVoxel.bat` 还会用旧 `MultiBunny` hint 覆盖脚本默认值，排障时很容易误判成“脚本没切到 sparse layout”。
- 改 `MultiBunny` 的布局或 cache 前缀时，除了 Python 入口，也要同步检查 bat launcher 里所有显式 scene hint 和 warning cache 路径；否则 UI 能跑起来，但人看到的是旧文件名和旧基线。
