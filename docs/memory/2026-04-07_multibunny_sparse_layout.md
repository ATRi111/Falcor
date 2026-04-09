# 2026-04-07 MultiBunny Sparse Layout

- `MultiBunny` 如果继续沿用显式 `HYBRID_VOXEL_CACHE_FILE`，一旦改了阵列密度、兔子 scale 或 scene bounds，就必须同步切新的 cache 前缀/文件名；否则 `ReadVoxelPass` 会稳定读回旧布局的 bin，画面看起来像“改了 scene 但 voxel 没变”。
- 这次把 10x10 阵列改成 5x5、同时把单兔 scale 翻倍时，为了保持原阵列的大致铺开范围，spacing 不能继续用 `0.34`，而应改成 `0.765`（旧总 span `9 * 0.34` 除以新间隔数 `4`）。
