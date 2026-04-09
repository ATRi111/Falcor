# 2026-04-06 Plan6 Phase5 Accepted-Route Limit

- 仅把 Phase5 推进到 per-solid-voxel accepted-route，而不扩 voxel payload/layout 时，中距离 takeover 仍可能出现“mesh 已退、voxel 侧却把目标物体渲染成墙/空位”的残留现象；触发条件是目标物体与别的实例共享 mixed voxel，且该 voxel 的 dominant BSDF/ellipsoid 仍属于别的实例。
- 原因是 accepted-route 只能决定 traversal/hit 是否放行，不能改写 mixed voxel 内实际用于着色和形状测试的 dominant payload；如果后续还要结构性消掉这类空窗，需要补 route-specific/secondary contributor payload，而不只是继续调 confidence threshold 或 route mask。
