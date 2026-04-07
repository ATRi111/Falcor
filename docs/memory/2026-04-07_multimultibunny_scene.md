# 2026-04-07 MultiMultiBunny Scene

- `MultiMultiBunny.pyscene` 是相对当前 `MultiBunny`（`6x6`, `spacing≈0.5996`, `scale≈2.4299`）再把实例密度提高到 `2x` 的独立场景；这次用 `8x8 + layout_scale≈0.6734`，把 `spacing` 缩到 `0.4038`、单兔 `scale` 缩到 `1.6364`，保持整体铺开范围仍接近当前 MultiBunny。
- 这个文件只新增 scene，不会自动接管现有 MultiBunny 的 voxel/blend launcher；如果后面要给它加 route script 或显式 cache，必须使用新的 scene hint / cache 前缀，不能继续复用 `MultiBunnyDense1p5Lerp`。
