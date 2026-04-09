# Plan5 ViewMode Performance Investigation Handoff

## 模块职责

澄清 plan5 当前 hybrid 里“切 `HybridCompositePass` 的 view mode”与“真正减少 mesh/voxel 正式执行成本”之间的边界，避免把 `MeshOnly` / `VoxelOnly` / `RouteDebug` 误当成性能模式。

## 结论

- 这次 `Composite / VoxelOnly / MeshOnly` 帧率几乎不变，结论是 **当前行为基本符合现设计，不是新回归**。
- 真正能做到“只进行一种正式渲染”的不是 `viewMode` 下拉框，而是 **每个实例的 route**。当前 Arcade 默认实例全部是 `Blend`，因此 mesh 正式链和 voxel 正式链都会继续覆盖整景。
- `MeshOnly` / `VoxelOnly` / `BlendMask` / `RouteDebug` / `ObjectMismatch` / `DepthMismatch` 这些模式本质上是 debug/view mode；其中多种模式还会因为 Phase5 的 debug full-source 修复故意放宽 route mask，以便看到完整源图。

## 用户新增硬目标

- 后续实现目标必须升级为：
  **所有物体在 `Mesh` 形态时，不再支付 `Voxel` 形态的正式渲染成本；所有物体在 `Voxel` 形态时，不再支付 `Mesh` 形态的正式渲染成本。**
- 这里的“去掉额外渲染开销”不是只改最终显示结果，也不是只在 `HybridCompositePass` 里切输出；必须让上游正式链本身不再执行该物体对应的另一种形态。
- 这个目标既适用于按实例 route 的对象级切换，也适用于未来如果引入全局性能模式时的整景切换；无论控制入口是什么，都不能再出现“画面只看单路，但 profiler 里另一条正式链仍完整存在”的情况。
- 新方案不能通过删除当前 debug full-source 逻辑来“伪造”性能提升；`MeshOnly` / `VoxelOnly` / `RouteDebug` 等调试视图与“真正减少正式成本”的执行模式必须明确分离。
- 后续验收口径必须包含 profiler 证据：当对象或整景被切到单一形态时，另一条正式链的关键 pass 耗时必须明显下降或从执行列表中消失，而不是只看 FPS 小幅波动。

## 代码证据

- `scripts/Voxelization_HybridMeshVoxel.py`
  `render_graph_hybrid()` 无论输出 mode 是什么，都会固定创建并连接：
  `MeshGBuffer -> MeshStyleDirectAOPass -> HybridCompositePass`
  `VoxelizationPass -> ReadVoxelPass -> RayMarchingDirectAOPass -> HybridCompositePass`
  `HybridBlendMaskPass -> HybridCompositePass`
- `Source/RenderPasses/HybridVoxelMesh/HybridCompositePass.ps.slang`
  `MeshOnly` / `VoxelOnly` 只是在最后一层 shader 里切 `meshColor` 或 `voxelColor` 输出，不会回头裁掉上游 pass。
- `Source/RenderPasses/GBuffer/GBuffer/GBufferRaster.cpp`
  hybrid graph 的 mesh route mask 来自脚本固定配置 `Blend|MeshOnly`；当前 Arcade 默认全是 `Blend`，所以 mesh raster 仍覆盖整景。
- `Source/RenderPasses/Voxelization/RayMarchingDirectAOPass.cpp`
  hybrid graph 的 voxel route mask 固定为 `Blend|VoxelOnly`；当前 Arcade 默认全是 `Blend`，所以 voxel ray march 仍覆盖整景。
- `Source/RenderPasses/HybridVoxelMesh/HybridCompositePass.cpp`
  debug full-source 标记 `HybridMeshVoxel.requireFullMeshSource/requireFullVoxelSource` 只服务调试视图，不代表全局单路执行。

## Profiler 证据

用户在 2026-04-05 提供的 Mogwai profiler 截图已经足够说明问题：

- `Composite`
  FPS `73.2`
  `RayMarchingDirectAOPass ~ 8.91 ms`
  `MeshStyleDirectAOPass ~ 2.34 ms`
  `MeshGBuffer ~ 1.00 ms`
  `HybridCompositePass ~ 0.45 ms`
- `VoxelOnly`
  FPS `73.9`
  `RayMarchingDirectAOPass ~ 8.80 ms`
  `MeshStyleDirectAOPass ~ 2.34 ms`
  `MeshGBuffer ~ 1.00 ms`
  `HybridCompositePass ~ 0.45 ms`
- `MeshOnly`
  FPS `73.4`
  `RayMarchingDirectAOPass ~ 8.84 ms`
  `MeshStyleDirectAOPass ~ 2.34 ms`
  `MeshGBuffer ~ 1.00 ms`
  `HybridCompositePass ~ 0.45 ms`

从这三组数据可以直接看出：

- voxel 主成本 `RayMarchingDirectAOPass` 没掉；
- mesh 主成本 `MeshStyleDirectAOPass + MeshGBuffer` 也没掉；
- `VoxelizationPass` 和 `ReadVoxelPass` 为 `0 ms`，说明 steady state 下主要瓶颈不是 cache 生成/读取；
- `ToneMapper` / `renderUI` 很小，不是这次“切模式没变快”的主因。

## 当前正确表述

- `Composite`：
  会按照实例 route 做 selective execution；但如果实例 route 全是 `Blend`，那两条正式链仍然都要跑。
- `MeshOnly` / `VoxelOnly`：
  当前只是“只看 mesh 源图 / 只看 voxel 源图”的视图，不是“强制全局只执行 mesh / voxel”。
- `RouteDebug` / `BlendMask` / `ObjectMismatch` / `DepthMismatch`：
  明确属于 debug 视图，不应期待性能提升。

## 如果后续要做真正的性能模式

不要复用当前 `viewMode` 语义，避免再次破坏已修好的 debug full-source 逻辑。更稳妥的最小方案是新增一个独立的执行模式开关，例如：

- `DefaultRoute`
- `ForceMeshPipeline`
- `ForceVoxelPipeline`

并让它单独驱动 graph / pass 级执行裁剪，例如：

- `ForceMeshPipeline`
  直接走 mesh pipeline，跳过 `RayMarchingDirectAOPass` 与 `HybridCompositePass`，或让 graph 输出直接来自 mesh/tone mapper。
- `ForceVoxelPipeline`
  直接走 voxel pipeline，跳过 `MeshGBuffer` / `MeshStyleDirectAOPass` / `HybridBlendMaskPass` / `HybridCompositePass` 的 mesh 依赖。

关键原则是：

- 保留当前 `HybridCompositePass.viewMode` 作为 debug/view 语义；
- 把“看什么”与“算什么”彻底分开。
- 无论是对象级 route 还是全局性能模式，最终都要满足“物体处于哪种形态，就只支付哪种形态的正式渲染成本”。

## 后续优先看

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
