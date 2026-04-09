# 2026-04-05 Plan4 Phase0 Baseline

- `Voxelization_MainlineDirectAO.py` 如果要在 `--scene` 启动时复现固定参考机位，不能只在脚本顶层直接改 `m.scene.camera`；场景绑定可能晚于脚本执行，正确做法是用 `m.sceneUpdateCallback` 做一次性相机落位。
- `Arcade` 的 far 参考机位不能沿默认视线无限后拉；一旦退得过多，Mogwai 窗口截图会混入房间外结构。阶段0只需要保守后拉并用窗口级截图复核。
