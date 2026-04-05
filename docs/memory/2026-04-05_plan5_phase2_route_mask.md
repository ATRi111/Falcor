# 2026-04-05 Plan5 Phase2 Route Mask

- `HybridBlendMaskPass`、`HybridCompositePass`、`HybridMeshDebugPass` 只要在 fullscreen shader 里读取 `gScene` 和 `HitInfo(vbuffer)` 做 route lookup，C++ 侧就必须同时注入 scene shader modules / type conformances / scene defines 并绑定 `gScene`；少任一项都会让 pass 退回成“只有屏幕空间输入、没有 scene route”的假 route-aware 状态。
- phase2 只把 route correctness 和 route-aware mask 跑通；当前 `Composite / MeshOnly / VoxelOnly / BlendMask` 仍会同时保留 mesh 与 voxel 正式链，真正减少双路径成本要等 phase5 selective execution。
- `Arcade` 的 near 机位里，`Blend` 椅子和房间主体都会落到绿色系，单看 `RouteDebug` 很难判断椅子是不是还在走距离带；phase2 验收必须把默认 `BlendMask` 和 `Chair:MeshOnly` override 对照着看，确认椅子从绿色渐变切成橙色常量，而不是只改了 overlay 着色。
- `Arcade` 里的街机柜当前是脚本显式配置的 `Cabinet -> MeshOnly`，不是距离带没生效；只要不改 `HYBRID_ROUTE_OVERRIDES` 或默认 route 表，它在任何远近机位都会保持 mesh 结果，而地板等未覆写对象仍按 builder 默认 `Blend` 参与距离带。
