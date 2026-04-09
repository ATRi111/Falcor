# 2026-04-09 Voxel Start-Inside Face Normal

- `RayMarchingDirectAO.ps.slang` 里主射线有一类命中会在“进入 voxel cell 时已经落在 fitted ellipsoid 内部”；旧逻辑要求 `x^T B x` 必须接近 `1`，这类壳内点会直接退回 `bsdfMainNormal`，现象就是 `NormalDebug` 异色和 `DirectOnly` 黑边在 silhouette/grazing 视角下精确对位。
- 规避方式是对壳内点先沿中心径向投回 ellipsoid 壳面再取 `B * shellOffset` 法线，同时只对轻微壳外点放宽容差；明显偏离 ellipsoid 的 conservative fallback 仍保留旧回退，避免把随机 cell-center 当成可靠命中面法线。
