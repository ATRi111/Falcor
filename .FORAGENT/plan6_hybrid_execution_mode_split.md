# plan6：hybrid 执行模式分离与真实单路成本执行手册

## 1. 目标定义

- 保持 `GeometryInstanceRenderRoute` 作为 **对象级 authoring route**：
  - `MeshOnly`
  - `VoxelOnly`
  - `Blend`
- 新增独立的 **execution/perf mode**，不要复用 `HybridCompositePass.viewMode`：
  - `ByObjectRoute`
  - `ForceMeshPipeline`
  - `ForceVoxelPipeline`
- 最终目标不是“只显示单路”，而是“只支付单路正式成本”：
  - `MeshOnly` 物体不再支付 voxel 正式链成本。
  - `VoxelOnly` 物体不再支付 mesh 正式链成本。
  - `Blend` 物体只有在当前帧 **确实需要双路** 时才支付双路成本。
  - 如果 `Blend` 物体在当前帧已经完全落到 mesh 侧，voxel 正式链必须被裁掉。
  - 如果 `Blend` 物体在当前帧已经完全落到 voxel 侧，mesh 正式链必须被裁掉。
- `HybridCompositePass.viewMode` 继续只表示 **debug/view mode**，不能再表示 execution mode。
- 不能破坏：
  - Phase5 debug full-source 修复
  - `Scene/Arcade/Arcade.pyscene` 默认入口
  - 已删除 Arcade 强制 route override 的基线

## 2. 非目标

- 不在第一版重构到 `VBufferRaster / VBufferRT`。
- 不做 per-object 独立 voxel cache。
- 不通过删除 debug full-source 逻辑来伪造性能提升。
- 不把验收标准降级成只看 FPS。

## 3. 当前基线结论

- `HybridCompositePass.viewMode` 现在只是最终显示切换；hybrid graph 仍固定创建 mesh + voxel 两条正式链。
- mesh selective execution 已经是真裁执行：
  - `GBufferRaster.cpp`
  - `Scene::rasterize()`
  - `Scene::createDrawArgs()`
- voxel selective execution 目前只到 hit-level：
  - `RayMarchingDirectAOPass.cpp` 只把 `instanceRouteMask` 传进 shader
  - `RayMarchingTraversal.slang` 在访问到 voxel offset 后才按 route 决定接受/跳过
- 当前 `blockMap` 是 route-agnostic：
  - `AnalyzePolygon.cs.slang` 只记录“该 block 里有 solid voxel”
  - 因此 `RayMarchingDirectAOPass` 仍会进入不该渲染的 block
- debug full-source 当前靠 dictionary 回写：
  - `HybridCompositePass.cpp`
  - `GBufferRaster.cpp`
  - `RayMarchingDirectAOPass.cpp`
  这套逻辑必须保留，但只能服务 debug 视图，不能继续扩展成 execution mode。

## 4. 推荐架构

后续实现必须明确分开 5 个概念：

1. `debug/view mode`
   - 入口：`HybridCompositePass.viewMode`
   - 职责：决定看什么

2. `execution/perf mode`
   - 入口：新增 `HybridExecutionMode`
   - 职责：决定算什么

3. `authoring route`
   - 入口：`GeometryInstanceRenderRoute`
   - 职责：对象原始意图

4. `resolved execution route`
   - 每帧从 `authoring route + 相机 + blend 距离带 + 对象范围` 推导
   - 取值建议：
     - `MeshResolved`
     - `VoxelResolved`
     - `NeedsBoth`

5. `global forced single-route mode`
   - `ForceMeshPipeline`
   - `ForceVoxelPipeline`

### 4.1 `Blend` 的正确执行语义

- `Blend` 不是“永远双路渲染”。
- `Blend` 只表示“允许根据当前帧位置落到 mesh / voxel / 双路中的任一种”。
- 最小充分做法：
  - 用对象 bounds 与 `blendStart / blendEnd` 判断该对象当前帧是否整体落在单侧
  - 只有 bounds 真正穿过 transition band 时，才标成 `NeedsBoth`

### 4.2 推荐落点

- 全局强制单路：放在 `scripts/Voxelization_HybridMeshVoxel.py` 的 graph 分支里解决。
- 对象级真实降成本：用两段式实现
  - mesh 侧继续复用 `Scene::rasterize()` draw filtering
  - voxel 侧新增 route-aware occupancy / block cull

## 5. 分阶段实施

### Phase 1：拆开 `viewMode` 和 `executionMode`

目标：

- 先把“看什么”和“算什么”彻底拆开。
- 提供 profiler 可直接验证的整景单路模式。

实现：

- 在 `scripts/Voxelization_HybridMeshVoxel.py` 新增 `HybridExecutionMode`
- `ByObjectRoute` 继续走 hybrid graph
- `ForceMeshPipeline` 只建：
  - `MeshGBuffer`
  - `MeshStyleDirectAOPass`
  - `ToneMapper`
- `ForceVoxelPipeline` 只建：
  - `VoxelizationPass`
  - `ReadVoxelPass`
  - `RayMarchingDirectAOPass`
  - `ToneMapper`
- 不要让 `ForceMeshPipeline / ForceVoxelPipeline` 经过 `HybridCompositePass.viewMode`

涉及文件：

- `scripts/Voxelization_HybridMeshVoxel.py`
- 如需入口同步：
  - `run_HybridMeshVoxel.bat`

通过条件：

- `ForceMeshPipeline` 下 profiler 里 voxel 正式链关键 pass 消失：
  - `RayMarchingDirectAOPass`
  - `HybridCompositePass`
  - `HybridBlendMaskPass`
- `ForceVoxelPipeline` 下 profiler 里 mesh 正式链关键 pass 消失：
  - `MeshGBuffer`
  - `MeshStyleDirectAOPass`
  - `HybridCompositePass`
  - `HybridBlendMaskPass`

### Phase 2：为 `Blend` 引入每帧 `resolved execution route`

目标：

- 不只优化显式 `MeshOnly / VoxelOnly`。
- `Blend` 物体在当前帧如果整体落到单侧，也必须裁掉另一条正式链。

实现：

- 新增每帧 classification：
  - `MeshOnly -> MeshResolved`
  - `VoxelOnly -> VoxelResolved`
  - `Blend`：
    - bounds 全在 `blendStart` 内：`MeshResolved`
    - bounds 全在 `blendEnd` 外：`VoxelResolved`
    - bounds 穿过 transition band：`NeedsBoth`
- 不要覆写 `GeometryInstanceRenderRoute`
- 新增独立 runtime resolved-route 数据，供 mesh / voxel 正式链消费

涉及文件：

- `scripts/Voxelization_HybridMeshVoxel.py`
- `Source/Falcor/Scene/Scene.cpp`
- `Source/Falcor/Scene/Scene.h`
- 如当前 scene API 不够用，补 instance bounds / radius 查询 helper

通过条件：

- 在 `ByObjectRoute` 下，`Blend` 物体如果当前帧已完全落到 mesh 侧，voxel 正式链关键耗时明显下降。
- 在 `ByObjectRoute` 下，`Blend` 物体如果当前帧已完全落到 voxel 侧，mesh 正式链关键耗时明显下降。
- 只有真正跨 transition band 的 `Blend` 物体还支付双路成本。

### Phase 3：让 mesh 正式链消费 `resolved execution route`

目标：

- mesh 侧不仅按 authoring route 裁剪，还要按 `resolved execution route` 裁剪。

实现：

- 让 `GBufferRaster` 传入的 route/filter 改为 resolved-route 结果
- 继续使用 `Scene::rasterize()` draw filtering，不回退到屏幕空间 discard

涉及文件：

- `Source/RenderPasses/GBuffer/GBuffer/GBufferRaster.cpp`
- `Source/Falcor/Scene/Scene.cpp`
- `Source/Falcor/Scene/Scene.h`
- `scripts/Voxelization_HybridMeshVoxel.py`

通过条件：

- `MeshResolved + NeedsBoth` 才进入 mesh 正式链
- `VoxelResolved` 对象不会再出现在 mesh draw args 里

### Phase 4：让 voxel 正式链从 hit-level 变成 block-level cull

目标：

- voxel 侧不再“进了 block 再判断该不该渲染”。

实现：

- 新增独立 route-prepare pass，位置放在：
  - `ReadVoxelPass` 之后
  - `RayMarchingDirectAOPass` 之前
- 基于：
  - `dominantInstanceID`
  - `identityConfidence`
  - 每帧 `resolved execution route`
  派生 route-aware occupancy
- 第一版先做 **block-level**：
  - `RouteBlockMapMesh`
  - `RouteBlockMapVoxel`
  - 或等价资源
- `RayMarchingTraversal.slang` 先按 route-aware block map 决定是否深入 block
- 低 confidence / invalid identity 保守处理，不强裁

涉及文件：

- 新增 route-prepare pass
- `Source/RenderPasses/Voxelization/ReadVoxelPass.cpp`
- `Source/RenderPasses/Voxelization/RayMarchingDirectAOPass.cpp`
- `Source/RenderPasses/Voxelization/RayMarchingTraversal.slang`
- `scripts/Voxelization_HybridMeshVoxel.py`

通过条件：

- 当视野主要是 `MeshResolved` 物体时，`RayMarchingDirectAOPass` 相比 `NeedsBoth` 明显下降
- `poster` 不会在 debug 视图下再次读黑
- `ObjectMismatch / DepthMismatch` 不出现大面积回归

### Phase 5：只有 profiler 证明还不够时，才做 cell-level / cache 扩展

目标：

- 只在 block-level cull 仍然不够时继续下钻。

实现：

- 为每个 solid voxel 派生 route bit / accepted route mask
- 如果 transient 派生成本仍高，再评估是否修改 cache layout

涉及文件：

- `RayMarchingTraversal.slang`
- `RayMarchingDirectAOPass.cpp`
- 只有确定改 layout 时才动：
  - `VoxelizationShared.slang`
  - `ReadVoxelPass.cpp`
  - `VoxelizationPass.cpp`
  - `AnalyzePolygon.cs.slang`

通过条件：

- 相比 Phase 4，voxel 正式链继续可测下降
- 如果改了 cache layout，旧 cache 必须显式失效并重生

## 6. 风险点

- 最大风险是再次把 `viewMode` 和 `executionMode` 混在一起。
- `Blend` 的真实降成本不能只靠 `authoring route`；必须引入每帧 `resolved execution route`。
- 当前 voxel identity 是 dominant-instance 语义；低 confidence 体素必须保守，否则最先坏的是边缘和 mismatch debug。
- 默认 Arcade 现在基本全是 `Blend`；如果不人为构造单侧 `Blend` 对照，就很容易误判“没降成本”。

## 7. 验证方法

- 必须看 Mogwai profiler，不接受只看 FPS。
- 关键验收对象：
  - 一个显式 `MeshOnly`
  - 一个显式 `VoxelOnly`
  - 一个 `Blend` 但当前帧整体落 mesh 侧
  - 一个 `Blend` 但当前帧整体落 voxel 侧
  - 一个 `Blend` 且当前帧确实跨 band
- 关键 pass：
  - mesh：`MeshGBuffer`、`MeshStyleDirectAOPass`
  - voxel：`RayMarchingDirectAOPass`
  - hybrid：`HybridBlendMaskPass`、`HybridCompositePass`
- debug 视图必须全保留：
  - `Composite`
  - `MeshOnly`
  - `VoxelOnly`
  - `RouteDebug`
  - `BlendMask`
  - `ObjectMismatch`
  - `DepthMismatch`
  - `VoxelDepth`
  - `VoxelNormal`
  - `VoxelConfidence`
  - `VoxelRouteID`
  - `VoxelInstanceID`

## 8. 通过条件

- `viewMode` 与 `executionMode` 已彻底分离。
- `ForceMeshPipeline / ForceVoxelPipeline` 下，被关闭的正式链关键 pass 在 profiler 中消失。
- `MeshOnly / VoxelOnly` 物体只支付单路正式成本。
- `Blend` 物体只有在当前帧确实跨 transition band 时才支付双路成本。
- 当 `Blend` 当前帧已整体落到单侧时，另一条正式链关键耗时必须明显下降或消失。
- debug full-source、Arcade 默认入口、无强制 route override 这三项基线不回归。

## 9. 回归项

- 不回退 `docs/handoff/2026-04-05_plan5_phase5_meshonly_debug_fix_handoff.md` 的修复。
- 不回退 `Scene/Arcade/Arcade.pyscene` 默认入口。
- 不恢复 `scripts/Voxelization_HybridMeshVoxel.py` 中的 Arcade 强制 route 表。
- 继续 smoke：
  - `scripts/Voxelization_MainlineDirectAO.py`
  - 当前 hybrid debug 视图

## 10. 后续 AI 起手顺序

1. 先做 Phase 1
2. 然后直接做 Phase 2
3. 只有 Phase 2 跑通后，再做 Phase 4

起手理由：

- 如果不先拆 `viewMode / executionMode`，后面所有 profiler 讨论都会继续混乱。
- 如果不先补 `Blend -> resolved execution route`，后面只优化显式 `MeshOnly / VoxelOnly` 仍然不满足目标。
