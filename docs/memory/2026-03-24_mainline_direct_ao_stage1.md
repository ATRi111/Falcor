# 2026-03-24 Mainline DirectAO Stage1

- 只编 `Voxelization` 目标时，`build\windows-vs2022\bin\Release` 里可能还没有 `Mogwai.exe`；如果要做脚本启动烟测，必须额外编一次 `Mogwai`，否则会误判成脚本或 pass 注册失败。
- 新 voxel 全屏 pass 在阶段 1 可以先只对齐 `ReadVoxelPass` 的输入契约、shader 里输出纯色；一旦 `VoxelizationBase.cpp` 完成注册并且 `CMakeLists.txt` 把 `.ps.slang` 加入 `target_copy_shaders()`，Mogwai 就能先把新图拉起来。
- 如果 `RayMarchingDirectAOPass` 在 stage 1 纯色 shader 阶段就把 `mpScene->getTypeConformances()` 传给 `FullScreenPass`，命令行同时带 `--scene` 和 `--script` 会在 program link 阶段报 `DualHenyeyGreensteinPhaseFunction ... was not found`；原因是 shader 还没导入 scene 接口类型，现阶段应先不传 scene conformances，等后续 shader 真正使用 scene 再成对接回去。
