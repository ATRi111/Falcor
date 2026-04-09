# 2026-04-09 Voxel BRDF Lobe Quantization

- `RayMarchingDirectAO` 的 `UnshadowedDirect` 仍然复现和 `DirectOnly` 相同的黑块，说明问题不在 scene visibility / AO，而在 `bsdf.eval(lightDir, viewDir, h)` 这条 BRDF 响应链路本身。
- `Voxel/ABSDF.slang` 里的 `NormalIndex()` 先把所有法线折到 `y>=0`，再只按 `±X / ±Z` 四个桶聚合 `LOBE_COUNT=4`；对 `MultiMultiBunny` 这类连续曲面，这会把 body/ear 上的法线分布硬切成块，direct lighting 会跟着出现 voxel 级的块状暗斑。
