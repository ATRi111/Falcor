# 2026-04-08 Hybrid Composite Foreground Epsilon

- `Composite` 在同时存在 mesh 命中和 voxel 命中时，如果直接复用 `DepthMismatch` 那套 `0.2 / 5%` 的宽容差做前景判定，高机位下贴近地面的 voxel 兔子下半身会被 floor 抢走，表现成“兔子只剩半只”。
- 规避方式是把“debug 用的深度容差”和“前景抢占 epsilon”分开；前景选择只能用更小的 epsilon，否则 floor 这种深度非常接近但明显在后面的 mesh 仍会吞掉 voxel 前景。
