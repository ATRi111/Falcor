# 2026-04-08 MultiMultiBunny Launcher Defaults

- 把 `run_MultiBunny_Voxel.bat` / `run_VoxelBunny_Blend.bat` 从 `MultiBunny` 切到 `MultiMultiBunny` 时，不能只改 `--scene`；`HYBRID_SCENE_HINT`、`HYBRID_CPU_SCENE_NAME` 和 `HYBRID_VOXEL_CACHE_FILE` 也要同步换成新的 scene 前缀，否则脚本会继续读写旧的 `MultiBunnyDense1p5Lerp` cache 语义。
- `MultiMultiBunny` 的实际 CPU voxel cache 文件名是 `MultiMultiBunny_(128, 9, 128)_128.bin_CPU`，不是沿用旧场景估出来的 `(128, 16, 128)`；launcher 如果写错，会每次都误判 cache 缺失并重复走生成路径。
- 用 `Start-Process` 对这些 `.bat` 做 GUI smoke 时，结束掉 bat/cmd 不一定会带走子进程 `Mogwai.exe`；验证后要显式检查并清理残留 `Mogwai`，否则会污染下一轮启动和日志判断。
