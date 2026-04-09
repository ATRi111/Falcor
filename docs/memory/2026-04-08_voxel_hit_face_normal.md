# 2026-04-08 Voxel Hit Face Normal

- `RayMarchingDirectAO.ps.slang` 之前把 `SurfaceBRDF::getMainNormal(viewDir)` 同时当成 `NormalDebug` 输出和 shadow/AO 射线偏移法线；在 `MultiMultiBunny 512` 这类曲面 silhouette 处，dominant lobe 不等于主射线 first-hit 面法线，现象就是边缘发黑、`NormalDebug` 彩边会随视角变化。
- 主射线命中时实际上已经有 ellipsoid clip 点 `hit.cell` 和 `pBuffer[offset]`；运行时优先用隐式面梯度 `B * (p - center)` 恢复命中面法线，只在 conservative fallback 时退回 BSDF 主法线，能在不改 voxel BRDF 聚合逻辑的前提下稳定修正 debug/offset 法线。
