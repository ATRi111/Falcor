# 2026-04-09 Voxel BlackBlock Attempts And Rollback

- 这轮对 voxel 黑块依次试过 hit-face normal、start-inside/fallback 分类、scene visibility 分类、`UnshadowedDirect`、平滑 BRDF、平均法线和半球朝向修正；其中 `UnshadowedDirect` 仍保留同样黑块，说明 AO 和 shadow visibility 都不是主因。
- `FaceNormalMask` / `LightVisibilityMask` 和用户机位下的黑块都对不上；当前最可疑的仍是 `ABSDF` 的 4-lobe 法线分桶与 direct BRDF 响应，但本轮没有得到稳定修复，因此源码先回退到 `7db5f9ada617a00fa39ff636ab36abaff9af4c8d` 基线，只保留文档供后续继续查。
