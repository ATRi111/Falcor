# 2026-04-08 Voxel Silhouette Self Shadow

- `RayMarchingDirectAO` 里 residual 黑边的主因不在 AO；把 direct-light scene visibility 临时强制成 `1` 后，近景 silhouette 黑边会明显消失，说明问题来自 shadow ray 的 receiver-side self-shadow。
- 这类黑边和视角强相关，不能只按 `NdotL` 调 shadow bias；需要把 `NdotV` 也纳入 near-receiver 忽略策略，或直接对 view-grazing 像素衰减 voxel shadow visibility，否则相机一转边缘又会发黑。
