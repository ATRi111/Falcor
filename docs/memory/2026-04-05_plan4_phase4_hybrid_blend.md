# 2026-04-05 Plan4 Phase4 Hybrid Blend

- Stage4 的 hybrid graph 里，`RayMarchingDirectAOPass` 在 `outputResolution=0` 时会固定产出 `1920x1080`，而 mesh `GBufferRaster` 默认跟 Mogwai framebuffer 走；如果两边分辨率不一致，后续 `HybridCompositePass` 很容易在 graph 编译或接线时踩到尺寸不一致问题。规避方式是像本轮脚本一样，在 hybrid 模式下显式把 Mogwai framebuffer 对齐到 voxel 输出分辨率。
- Windows 下做 Stage4 增量构建时，如果上一轮验收留下的 `Mogwai.exe` 还挂着，`Falcor.dll` 会在重新链接阶段直接报 `LNK1104` 无法打开文件，看起来像新 pass 编译坏了。真正原因是运行中的 Mogwai 占住了 DLL；补编前先关掉旧窗口，再串行重跑 `HybridVoxelMesh` 和 `Mogwai`。
