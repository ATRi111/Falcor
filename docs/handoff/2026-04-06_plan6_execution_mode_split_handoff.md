# Plan6 Execution Mode Split Planning Handoff

## 模块职责

本轮没有实现新逻辑，只把计划文档改成更短、更像执行手册的版本，并补上新的硬目标：不是只有显式 `MeshOnly / VoxelOnly` 才要降成本，`Blend` 物体在当前帧如果已经整体落到单侧，也必须裁掉另一条正式链。

## 当前状态

- 新计划文档已落到 `.FORAGENT/plan6_hybrid_execution_mode_split.md`，并已改成精简、自包含版本；后续 AI 不应该再先回到旧上下文里重新做长篇架构讨论。
- 代码基线结论已收敛：
  - mesh selective execution 已经正确下沉到 `GBufferRaster -> Scene::rasterize()` 的 draw filtering。
  - voxel selective execution 目前只在 `RayMarchingTraversal.slang` 的 hit-level 接受阶段生效，`blockMap` 仍是 route-agnostic。
  - `HybridCompositePass.viewMode` 仍然只是显示/调试模式，不能复用成 execution mode。
  - 当前 debug full-source 修复必须保留，不能拿掉来“伪造”性能提升。
- plan6 推荐的最小充分架构是：
  - graph/script 层新增独立 `HybridExecutionMode`
  - `Blend` 先引入每帧 `resolved execution route`，不能再把 `Blend` 视为“永远双路”
  - mesh 侧继续沿用 `Scene::rasterize()` draw filtering
  - voxel 侧新增独立 route-prepare pass，先做 route-aware block-level cull，再按 profiler 决定是否继续做 cell-level / cache layout 扩展

## 优先文件

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan6_hybrid_execution_mode_split.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`

## 后续实施建议

- 先做 plan6 Phase 1：在 `scripts/Voxelization_HybridMeshVoxel.py` 增加独立 execution mode，并让 `ForceMeshPipeline / ForceVoxelPipeline` 通过 graph 分支直接去掉另一条正式链。
- 然后直接做 plan6 Phase 2：给 `Blend` 增加每帧 `resolved execution route`，确保“当前帧已经整体落到 mesh / voxel 单侧的 Blend 物体”不再继续支付另一条正式链成本。
- Phase 1/2 都不要回退当前 debug full-source dictionary 修复；那是 debug 视图可见性的既有基线。
- 做 profiler 验收时，不要只拿默认全 `Blend` 的 Arcade；要用临时 route override 或专门测试 scene 构造：
  - `MeshOnly`
  - `VoxelOnly`
  - `Blend 但当前帧单侧`
  - `Blend 且当前帧跨 band`

## 验证边界

- 本轮是 docs-only 交付，没有跑编译或 Mogwai smoke。
- 后续真正实施代码时，验收必须以 Mogwai profiler 为主，不能只看 FPS。
