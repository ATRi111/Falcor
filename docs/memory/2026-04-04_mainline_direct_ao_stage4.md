# 2026-04-04 Mainline DirectAO Stage4

- Stage4 的 `AOOnly` 如果直接输出线性的 `ao.xxx`，在 `ToneMapper` 后很容易看起来像“几乎全白的占位图”；原因是稳定 AO baseline 的遮蔽值大多接近 1，调试视图要额外做更强的曲线映射，避免误判成 AO 没生效。
- 主线 AO 要保持单帧稳定，方向打散只能来自 `hit.cellInt` 的稳定 hash；一旦把 `frameIndex` 或逐帧随机旋转重新混回 `macroAO`，相机静止时也会重新出现 shimmer。
