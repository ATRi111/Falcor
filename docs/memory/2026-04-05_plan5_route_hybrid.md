# 2026-04-05 Plan5 Route Hybrid

- 两份 deep research 都收敛到 `per-instance` 路由，但直接把 mesh 前端整体切到 VBuffer-first 会和当前 `GBufferRaster + MeshStyleDirectAOPass` 链路绑成一次大重构；更稳妥的主线是先把 route、voxel identity 和 selective execution 打通，再把 VBuffer/HLOD 当成 profiling 触发的后续优化。
- 像 `plan4_object_route_analysis_handoff`、`future_hybrid_renderer_vision_handoff` 这类只承担过渡入口职责的 handoff，在 `plan5.md` 成为主入口后应直接删除；否则后续 Agent 很容易被搜索结果带回 pre-research 阶段。
