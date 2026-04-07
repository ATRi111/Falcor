# 2026-04-07 MultiBunny Density 1p5 Layout

- `MultiBunny.pyscene` 如果要在保持大致铺开范围的同时把实例密度提高到 `1.5x`，单纯把 `5x5` 改成 `6x6` 不够；这次用 `6x6 + layout_scale≈0.7838`，把 `spacing` 缩到 `0.5996`、单兔 `scale` 缩到 `2.4299`，这样实例密度接近目标且不会把阵列重新撑得太开。
- MultiBunny 相关 voxel/blend 入口继续显式绑定 cache 文件时，只要布局或 scale 再改，就必须同步切新的 scene hint / cache 前缀；否则 `ReadVoxelPass` 会稳定读回旧布局的 bin，误判成“scene 改了但 voxel 没变”。
