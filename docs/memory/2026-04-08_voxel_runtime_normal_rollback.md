# 2026-04-08 Voxel Runtime Normal Rollback

- `RayMarchingDirectAO.ps.slang` / `Shading.slang` 上针对 silhouette 黑边的 runtime normal 修正尝试在当前 `MultiMultiBunny 512` 场景下没有稳定收敛，已整体回退；当前基线只保留 `ReadVoxelPass` 的“默认读取上一次手动读取 cache”逻辑和对应 launcher/script 默认值。
- 用 `m.frameCapture` 脚本化拉起 Mogwai 抓图时，本机反复在 `ReadVoxelPass: auto-reading cache ...` 之后以 `0xC0000005` 退出；做可视化验收优先走可见窗口而不是自动抓帧。
