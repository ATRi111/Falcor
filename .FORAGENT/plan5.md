# plan5：对象级 hybrid 路由与选择性执行实施计划

## 1. 文档定位

- 本文件是当前唯一有效的 hybrid 主计划，专门回答“每个物体独立决定走 voxel / mesh / blend，且非 blend 物体只跑一种正式渲染”的落地路径。
- 截至 2026-04-05，Phase1-4 已完成；当前代码基线已经具备 `per-instance route`、`route-aware mask`、`voxel identity / depth / normal / confidence`，以及对象级 composite 与 `ObjectMismatch / DepthMismatch` 调试口。
- 当前可验收展示基线仍然是 voxel 主线 `scripts\Voxelization_MainlineDirectAO.py`；当前 `scripts\Voxelization_HybridMeshVoxel.py` 是 plan5 的开发基线，不是最终验收口径。

## 2. 方案结论

两份 deep research 的交集结论是对的：

- 路由粒度应以 `per-instance` 为主，而不是 `per-material` 或全局距离带。
- 仅靠当前 `HybridBlendMaskPass` 的屏幕空间距离混合，无法满足“非 blend 物体只跑一种正式渲染”的要求。
- voxel 路径必须补 `identity + depth/normal + confidence` 之类的额外信号，否则 composite 只能继续做盲目 `lerp`。

但两份报告的建议强度不同：

- 一份更偏向“沿当前 `GBufferRaster + MeshStyleDirectAOPass` 继续演进，再补对象级路由”。
- 另一份更偏向“尽早切到 VBuffer-first 架构”。

本仓库的推荐落地顺序是：

1. 先做 `per-instance route + identity-augmented voxel contract`，把对象级路由和正确性打通。
2. 第一版继续沿用当前 mesh 侧 `GBufferRaster` 入口，不立即把整个 mesh 前端切到 `VBufferRaster / VBufferRT`。
3. 等 route、composite 和 selective execution 真正跑通后，再用 profiling 决定是否继续做 `VBuffer-first` 或 `cluster/HLOD voxel proxy`。

这样选的原因是：

- 当前仓库的 mesh 正式链已经建立在 `GBufferRaster -> MeshStyleDirectAOPass` 上，直接切 VBuffer-first 会把“对象级路由”和“mesh 前端大重构”绑在一起，改动面过大。
- 当前真正的硬阻塞不是 mesh 着色入口，而是 scene 侧没有 route、voxel cache 没有 identity、composite 没有 depth/normal/confidence。
- 如果这些问题不先解决，即使切成 VBuffer-first，也仍然只能得到“更复杂的全局双路径”。

## 3. 当前状态与关键缺口

### 3.1 已有基础

- `HybridVoxelMesh` 目录已经有 mesh debug、mesh style、blend mask、composite 的基本骨架。
- `scripts\Voxelization_HybridMeshVoxel.py` 已经能切换 mesh-only 调试和第一版 hybrid composite。
- `GBufferRaster` 已能提供 `vbuffer` 与 `mtlData`，scene 侧也已有 `GeometryInstanceData`。

### 3.2 当前缺口

- 当前 hybrid graph 在 `Composite / MeshOnly / VoxelOnly / BlendMask / ObjectMismatch / DepthMismatch` 下仍然会同时跑 mesh 和 voxel 两条正式出图链；Phase4 只完成 correctness，没有完成 selective execution。
- 当前 `Blend` 的最终权重已经会联合使用 route、mesh depth、voxel depth 和 voxel confidence，但仍以 `HybridBlendMaskPass` 的距离带作为 base signal；这符合 Phase4 的 correctness 目标，不代表 Phase5 的成本目标已经完成。
- 当前 `Scene::rasterize()` 仍然按全场景 draw list 走，mesh 分支还做不到只画 `MeshOnly + Blend` 实例。

### 3.3 本计划的硬性原则

- `screen-space discard` 或 composite-only 单路显示，只能作为过渡调试手段，不算完成“非 blend 物体只跑一种正式渲染”。
- 只要 mesh 分支仍在给 `VoxelOnly` 实例做正式 shading，或者 voxel 分支仍在给 `MeshOnly` 实例做正式出图，本计划就不能算完成。

## 4. 推荐架构

### 4.1 路由粒度

主粒度采用 `per-instance`，只保留三种正式模式：

- `MeshOnly`
- `VoxelOnly`
- `Blend`

后续如果需要更激进的 far-field 优化，可以在 `Blend` 之外再引入 `VoxelProxy` / `ClusterProxy` 之类的扩展模式，但不是第一版必做。

### 4.2 路由数据归属

推荐把 route 的运行时热路径落在 `GeometryInstanceData.flags` 的空闲 bit 上，并保留一份更易编辑的 CPU 侧 authoring/config 入口。

具体建议：

- authoring 层可以先来自脚本、临时配置表、或实例名到 route 的映射。
- 真正给 shader / pass 消费的 runtime route 要镜像进 `GeometryInstanceData.flags`。
- 不要把 route 偷塞到 `materialID`、`meshID`、或临时 dictionary 里当正式契约。

原因：

- `GeometryInstanceData` 已经 CPU/GPU 双端可见，后续 mesh、vbuffer、ray query、voxel route helper 都能直接复用。
- 单独再给每个 pass 绑一份 route buffer 当然可行，但会把后续 pass 改动面放大，不适合作为第一版主契约。

### 4.3 mesh 前端

第一版继续保留：

- `GBufferRaster`
- `MeshStyleDirectAOPass`
- `HybridMeshDebugPass`

但要补三类信号：

- `instanceID` 可读入口
- `materialID / mtlData`
- route-aware debug / mask 输入

实现上不要求立刻把 `MeshStyleDirectAOPass` 改成 VBuffer-first。先让现有 mesh 正式链拿到对象身份并能配合 route 工作，再决定是否值得切 VBuffer-first。

### 4.4 voxel 前端

第一版不走 “per-object 独立 voxel cache” 或 “双 Scene 动态迁移”，而是在当前全局 voxel 表示上补 identity。

最小必要输出建议变为：

- `voxelColor`
- `voxelDirect`
- `voxelAO`
- `voxelDepth` 或 `voxelHitT`
- `voxelNormal`
- `voxelConfidence` / `voxelCoverage`
- `voxelRouteID` 或能追溯到 instance / cluster 的 ID

这里的关键不是立刻追求最理想的数据结构，而是让 composite 至少有能力判断：

- 这个 voxel 命中是不是应该参与 blend
- 它和 mesh 命中的是不是同一个逻辑对象
- 深度与法线是否一致到可以安全混合

### 4.5 composite 原则

最终 composite 必须遵守：

- `MeshOnly` 像素默认只取 mesh 正式结果。
- `VoxelOnly` 像素默认只取 voxel 正式结果。
- 只有 `Blend` 像素才允许双源混合。
- Blend 权重不能只靠距离；至少要叠加深度一致性和 voxel confidence。

## 5. 明确不做的路线

- 不再继续此前那条只面向全局 hybrid 收敛的“稳定性与性能收敛”路线；当前主线目标是对象级 selective execution。
- 第一版不做“按材质决定 route”。
- 第一版不做“两个完整 Scene 在帧间频繁搬迁实例”的架构。
- 第一版不做“为每个对象单独维护一整套碎片化 voxel brick/cache”的重设计。
- 在 route / identity / composite 没跑通前，不把整个 mesh 前端直接换成 VBuffer-first 主线。

## 6. 分阶段实施建议

### 6.1 Phase1：实例级 route 契约与调试底座

#### 目标

让场景里至少一批指定实例能明确标记为 `MeshOnly / VoxelOnly / Blend`，并在 GPU 侧稳定读到这个 route。

#### 主要改动区域

- `Source\Falcor\Scene\SceneTypes.slang`
- `Source\Falcor\Scene\Scene.slang`
- `Source\Falcor\Scene\SceneBuilder.cpp`
- 必要时补 route helper 或 authoring 入口
- `scripts\Voxelization_HybridMeshVoxel.py`

#### 关键要求

- route 的 authoring 和 runtime 表达必须分开考虑，但 runtime 必须落到 scene 实例数据。
- 至少给 `Arcade` 选出 3-5 个固定参考实例，后续都用它们做切换验证。
- 需要有 route debug 视图，不能只靠打印日志。

#### 风险

- 如果只把 route 放在脚本变量或 Python dictionary 里，后续 voxel / composite / ray query 都会重新发明一套读取方式，计划会立刻失控。

#### 通过条件

- 能在 Mogwai 中稳定看到实例 route overlay。
- 指定实例可以独立切到 `MeshOnly / VoxelOnly / Blend`，而不是只能整景切模式。

### 6.2 Phase2：mesh 身份布线与 route-aware mask

#### 目标

在不大改 mesh 前端的前提下，让现有 hybrid 图拿到 mesh 侧的对象身份，并把当前距离带 blend mask 升级为 “route + 距离带” 的第一版 mask。

#### 主要改动区域

- `scripts\Voxelization_HybridMeshVoxel.py`
- `Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.*`
- `Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.*`
- 必要时补 `vbuffer / mtlData` 接线

#### 关键要求

- `BlendMaskPass` 必须先判断 instance route，再决定是否继续使用距离带。
- `MeshOnly` 对象不能再被 mask 成“跟 voxel 结果做 lerp”。
- 先不强求真正去掉所有 mesh 分支成本，但要把逻辑正确性跑通。

#### 风险

- 如果继续只让 `HybridBlendMaskPass` 看 `posW`，后续再多的 voxel depth / normal 输出也救不了错误的 route 语义。

#### 通过条件

- `MeshOnly / VoxelOnly / Blend` 三类对象在当前 composite 调试图里能被明确区分。
- 把某个对象切到 `MeshOnly` 后，画面不再出现“明明不该 blend 还在跟 voxel 混”的结果。

### 6.3 Phase3：voxel identity 与多信号输出契约

#### 目标

扩展当前 voxel 侧 contract，让 ray march 结果至少能输出对象身份、深度、法线和 confidence/coverage。

#### 主要改动区域

- `Source\RenderPasses\Voxelization\VoxelizationShared.slang`
- `Source\RenderPasses\Voxelization\Shading.slang`
- `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- 如有必要，补 cache layout 或 prepare pass

#### 关键要求

- 明确一个稳定的 identity 语义：是 dominant instance、dominant cluster，还是别的 proxy ID。
- 只要一个 voxel 内存在多对象混合，就必须给出明确的 confidence/uncertainty 语义，不能假装 identity 永远精确。
- 不能只加 debug 输出而不把资源反射和脚本接线补齐。

#### 风险

- 直接把“最后一次写入的 instanceID”当正式 identity 很容易在共享 voxel 或细碎几何区域变得不稳定。

#### 通过条件

- 至少能单独查看 `voxelDepth / voxelNormal / voxelConfidence / voxelRouteID`。
- reference 物体切成 `VoxelOnly` 后，composite 能基于这些信号做正确判别。

### 6.4 Phase4：对象级 composite 与正确性闭环

#### 目标

把当前“全局距离带 lerp”升级成真正的对象级 composite：非 blend 物体只取单路结果，blend 物体才使用多信号混合。

#### 主要改动区域

- `Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.*`
- `Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.*`
- `scripts\Voxelization_HybridMeshVoxel.py`

#### 关键要求

- composite 至少要联合使用：
  - route mode
  - mesh depth
  - voxel depth/hitT
  - voxel confidence
- 增加 object mismatch / depth mismatch 调试模式，避免出现错混后只能凭肉眼猜。
- 保持 pre-tonemap 线性空间合成不变。

#### 风险

- 如果没有 mismatch debug 口，后续所有“边缘重影 / 空洞 / 过早切换”都会变成低效盲调。

#### 通过条件

- `MeshOnly / VoxelOnly / Blend` 三类对象在 near / mid / far 参考视角都表现正确。
- Blend 区不再仅由屏幕空间距离单独主导。

#### 当前实现结果

- 已于 2026-04-05 完成第一版：`MeshOnly` 默认只取 mesh，`VoxelOnly` 默认只取 voxel，只有 `Blend` 才允许双源混合。
- 当前 `Blend` 的实际 voxel 参与度由 `route + distance base weight + mesh depth + voxel depth + voxel confidence + object match` 共同决定；低 confidence 或对象不匹配时会保守退回 mesh。
- 当前新增的调试口为 `ObjectMismatch` 与 `DepthMismatch`；两者都已在 `Arcade` near 机位完成窗口级 smoke。

### 6.5 Phase5：真正去掉非 blend 物体的双路径正式成本

#### 目标

从“逻辑上已经对象级路由”推进到“成本上也已经对象级路由”，这是 plan5 的核心验收阶段。

#### 主要改动区域

- mesh 分支的 draw / raster 入口
- voxel 分支的 voxelization / read / march 入口
- 必要时涉及 `Scene::rasterize()` 调用路径

#### 关键要求

- mesh 正式分支必须停止为 `VoxelOnly` 实例做正式 shading。
- voxel 正式分支必须停止为 `MeshOnly` 实例做正式出图。
- `screen-space discard` 只能作为过渡调试，不能当最终结果报验。

#### 实施顺序建议

1. 先用 route-aware early-out 验证逻辑与资源接线。
2. 再把真正的实例级过滤推进到 mesh 正式 draw 和 voxel 正式路径。
3. 最后用 profiling 判断成本是否真的下降。

#### 风险

- 如果只完成 early-out 而没完成实例过滤，视觉上看似已经正确，但你最关心的“不要双路径并行渲整个场景”仍然没有解决。

#### 通过条件

- 混合场景下，`MeshOnly` 和 `VoxelOnly` 物体都不再支付另一条正式渲染路径的完整成本。
- 与当前 Stage4 hybrid 相比，至少要补一份明确的 profile 对比说明成本变化来自哪里。

### 6.6 Phase6：仅在 profiling 证明需要时再做的优化分支

#### 目标

只在 Phase5 做完后，根据实际瓶颈决定是否进一步切换 mesh 前端或引入 far-field proxy。

#### 可选方向

1. `VBufferRaster / VBufferRT` 前端升级
   - 适用条件：mesh raster / GBuffer 带宽已经成为主瓶颈。
2. `cluster / HLOD voxel proxy`
   - 适用条件：远景 voxel 仍需要更强的性能收益或更稳定的 proxy 表达。

#### 关键要求

- 这两个方向都不是默认必做项。
- 没有 profile 证据，不要为了“架构看起来更先进”就提前切换。

## 7. 验证与交付要求

### 7.1 功能验证

- 每个阶段都要保留 `Arcade` 的 near / mid / far 固定机位复核。
- 至少挑 1 个 `MeshOnly`、1 个 `VoxelOnly`、1 个 `Blend` 参考对象做窗口级截图对比。

### 7.2 视觉验证

- 同时保留：
  - final composite
  - route overlay
  - blend mask
  - mesh-only
  - voxel-only
  - depth mismatch / object mismatch

### 7.3 性能验证

- 从 Phase5 开始，必须给出与当前 Stage4 hybrid 的 GPU/CPU 成本对比。
- 如果某个阶段只改善了 correctness、没有减少成本，应在 handoff 里明确写出“为什么还没降成本”。

### 7.4 回归验证

- 每次跨 scene / scene core / voxel contract 的改动，都要额外 smoke `scripts\Voxelization_MainlineDirectAO.py`，确保当前 voxel 主线没被误伤。

## 8. 后续 Agent 的阅读顺序

1. `.FORAGENT\plan5.md`
2. `docs\handoff\2026-04-08_readvoxel_last_manual_cache_default_handoff.md`
3. `docs\handoff\2026-04-08_voxel_runtime_normal_rollback_handoff.md`
4. `docs\handoff\2026-04-05_plan5_phase4_object_composite_handoff.md`
5. `docs\handoff\2026-04-05_plan5_phase3_identity_contract_handoff.md`
6. `docs\handoff\2026-04-04_mainline_direct_ao_stage4_handoff.md`
7. `docs\memory\2026-04-05_plan5_phase4_object_composite.md`
8. `docs\memory\2026-04-05_plan5_phase3_identity_contract.md`
9. `docs\memory\2026-04-05_plan5_phase2_route_mask.md`
10. `scripts\Voxelization_HybridMeshVoxel.py`
11. `Source\RenderPasses\HybridVoxelMesh\*`
12. `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
13. `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
14. `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
15. `Source\Falcor\Scene\SceneTypes.slang`
16. `Source\Falcor\Scene\SceneBuilder.cpp`

## 9. 交付边界

- plan5 的完成标准不是“又做出一版全局 blend 更平滑的 composite”。
- plan5 的完成标准是：
  - 对象级 route 成立；
  - voxel 有 identity 与多信号输出；
  - 非 blend 物体不再并行支付两条正式渲染路径的成本；
  - 如果还需要更大幅度性能提升，再由 profiling 决定是否进入 VBuffer-first 或 voxel proxy 优化。
