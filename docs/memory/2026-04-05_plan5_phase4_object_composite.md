# 2026-04-05 Plan5 Phase4 Object Composite

- Phase4 的正式闭环要放在 `HybridCompositePass`，不是继续把 `HybridBlendMaskPass` 做成全能决策器；当前有效策略是让 `BlendMaskPass` 只保留 route + 距离基权重，再在 composite 里用 `meshPosW -> mesh depth`、`voxelDepth`、`voxelConfidence` 和 object match 做保守收口。
- `ObjectMismatch` / `DepthMismatch` 两个视图在 Arcade near 的正常结果会是“整体偏绿、只有轮廓和少量失配区域发红”；如果它们退回整屏纯绿或纯黑，先查 `MeshGBuffer.posW -> HybridCompositePass.meshPosW` 接线和 `Voxelization_HybridMeshVoxel.py` 的 `HYBRID_OUTPUT_MODE` 映射。
