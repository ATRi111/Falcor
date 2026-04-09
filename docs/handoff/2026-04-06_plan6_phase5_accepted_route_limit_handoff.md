# Plan6 Phase5 Accepted-Route Attempt Handoff

## 模块职责

在不破坏 Phase5 debug full-source、不改 `GeometryInstanceRenderRoute` authoring 语义、也不先动 cache layout 的前提下，把 voxel selective execution 从 Phase4 的 block-level route-aware cull 再推进一步：为每个 solid voxel 生成独立的 accepted-route mask，让 block 放行后，block 内 traversal/hit accept 不再只依赖 dominant-instance 的单点 route 判定。

## 本轮实际落地

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.h`
  新增 runtime resource 名 `solidVoxelAcceptedRouteMask`。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelRoutePrepare.cs.slang`
  `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelRoutePreparePass.cpp`
  `VoxelRoutePreparePass` 现在除 `routeBlockMapMesh/routeBlockMapVoxel` 外，还会输出每个 solid voxel 的 `acceptedRouteMask`：
  - invalid / low-confidence identity -> `AllRoutes`
  - trusted `NeedsBoth` -> `Blend`
  - trusted 单侧 route 且 `identityConfidence < 0.999` 的 mixed voxel -> 保守放宽到 mesh+voxel 单路都接受，避免 block 内继续因为 dominant-route 抖动先 reject
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
  `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
  `RayMarchingDirectAOPass` 新增对 `solidVoxelAcceptedRouteMask` 的可选输入；当 hybrid resolved-route selective execution 开启时，cell/hit accept 优先消费这份 per-solid mask，缺失时才退回旧的 `dominantInstanceID + resolvedRouteBuffer` fallback。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  hybrid graph 新增：
  `VoxelRoutePreparePass.solidVoxelAcceptedRouteMask -> RayMarchingDirectAOPass.solidVoxelAcceptedRouteMask`
- 补了验证脚本：
  - `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\validate_phase5_voxel_accepted_routes.py`
  - `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\capture_phase5_takeover_window.py`

## 验证结果

- 构建通过：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target GBuffer HybridVoxelMesh Voxelization Mogwai`
- Phase5 批验证输出：
  - `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\phase5_voxel_accepted_routes_validation.json`
- 当前结论不是“修好”，而是“定位更准”：
  - 这轮确实减少了 block 放行后、block 内仍按 dominant route 把 mixed solid voxel 过早 reject 的情况。
  - 但用户提供的手动截图已经确认：中距离 takeover 仍存在残留空窗，只是现象从“先消失再出现”进一步暴露成“voxel 已放行，但实际显示成墙/空位或别的实例主导”。

## 关键结论

- 这轮已经证明：**只做 per-solid accepted-route，不扩 voxel payload/layout，不足以结构性修掉 takeover 空窗。**
- 根因不再只是 Phase4 的 block-level 粒度不够，也不再只是 hit-level reject 过早，而是：
  - mixed voxel 虽然现在能被当前 execution route 接受
  - 但该 voxel 内真正用于椭球测试 / BSDF 着色 / normal / confidence 的 payload 仍是当前 cache 里唯一保存的 dominant contributor
  - 如果 dominant contributor 属于墙或别的实例，mesh 一退后，voxel 侧仍会显示成“错误接管”而不是 cabinet 自己
- 换句话说：
  - `accepted-route` 只能回答“这个 voxel 该不该被走到”
  - 但现在缺的是“被走到之后，应该用哪一路 contributor payload 去表示它”

## 后续该怎么做

下一位 AI 不要继续在 `identityConfidenceThreshold`、`resolvedRouteConfidenceThreshold`、`acceptedRouteMask` 的规则上小修小补；这条路已经验证不够。正确下一步应是最小必要的 payload/layout 扩展，目标是为 mixed voxel 提供 route-specific 或 secondary contributor 数据，让 voxel 侧在 MeshResolved/VoxelResolved 切换时不仅能“接受命中”，还能“命中正确的 payload”。

优先建议的落点顺序：

1. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationShared.slang`
   给 `VoxelData` 补最小附加 payload，至少能表达 dominant 之外的另一条 route-relevant contributor。
2. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
   不要只输出 `dominantInstanceID + identityConfidence`；需要在生成阶段把 secondary / route-specific contributor 的面积和 payload 一起写出来。
3. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass.cpp`
   `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
   明确升级 cache 文件布局；旧 cache 必须显式失效并说明重生方式。
4. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\PrepareShadingData.cs.slang`
   `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
   把新 payload 拆进 runtime shading buffer。
5. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
   `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
   traversal / hit accept 决定 route 后，真正选择对应 contributor payload，而不是继续默认读唯一 dominant payload。

## 截图与验证坑

- 批验证脚本默认会自退，不会挂 Mogwai；继续沿用 `validate_phase5_voxel_accepted_routes.py` 这类模式。
- 不要再用 uint 纹理 `to_numpy()` 当主验证。
- `window-render-capture` 在这台机子上对 Mogwai 不稳定，可能遇到：
  - `Loading Configuration` 与主窗口并存导致多窗口歧义
  - `Failed to query window bounds`
- 如果需要窗口证据，最稳的是：
  - 先把 Mogwai 调到指定机位
  - 让用户手动截图
  - 或者自己按主窗口句柄走 `GetWindowRect + CopyFromScreen` 兜底
- 启动后 10~18 秒内抓图太早时，很容易只得到白窗；白窗不能当结果。

## 下一个 AI 起手先看

- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-06_plan6_phase4_validation_and_block_limit.md`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-06_plan6_phase5_accepted_route_limit.md`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-06_plan6_phase5_capture_validation_pitfalls.md`
- `E:\GraduateDesign\Falcor_Cp\build\profiling\2026-04-06_plan6_phase5\phase5_voxel_accepted_routes_validation.json`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelRoutePrepare.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationShared.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
