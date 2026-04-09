# 2026-04-05 Plan5 Phase2 Route Mask

- `HybridBlendMaskPass`、`HybridCompositePass`、`HybridMeshDebugPass` 只要在 fullscreen shader 里读取 `gScene` 和 `HitInfo(vbuffer)` 做 route lookup，C++ 侧就必须同时注入 scene shader modules / type conformances / scene defines 并绑定 `gScene`；少任一项都会让 pass 退回成“只有屏幕空间输入、没有 scene route”的假 route-aware 状态。
- phase2 只把 route correctness 和 route-aware mask 跑通；当前 `Composite / MeshOnly / VoxelOnly / BlendMask` 仍会同时保留 mesh 与 voxel 正式链，真正减少双路径成本要等 phase5 selective execution。
- `Arcade` 的 near 机位里，`Blend` 椅子和房间主体都会落到绿色系，单看 `RouteDebug` 很难判断椅子是不是还在走距离带；phase2 验收必须把默认 `BlendMask` 和 `Chair:MeshOnly` override 对照着看，确认椅子从绿色渐变切成橙色常量，而不是只改了 overlay 着色。
- `Arcade` 曾经有脚本显式 route 覆写（`Cabinet -> MeshOnly`、`poster -> VoxelOnly`），所以 phase2 的旧 `RouteDebug` 证据不能直接当成默认行为。2026-04-05 phase5 收尾已清空这些覆写，当前 Arcade 默认实例都会回退到 scene-builder 的 `Blend`。
