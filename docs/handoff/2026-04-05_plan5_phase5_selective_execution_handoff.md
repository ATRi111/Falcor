# Plan5 Phase5 Selective Execution Handoff

## 模块职责

plan5 Phase5 的执行成本收口基线。当前目标不是再改 composite correctness，而是让 hybrid 正式链按对象 route 做真正的 mesh/voxel selective execution。

## 当前状态

- `GBufferRaster` 新增 `instanceRouteMask` 属性，并通过新的 `Scene::rasterize(..., instanceRouteMask)` 入口驱动 route-aware raster；hybrid 正式 mesh 链现在只提交 `Blend + MeshOnly` 的 triangle-mesh instance，`VoxelOnly` 不再进入 depth/GBuffer 正式 draw。
- `Scene` 为 route-filtered raster 增加了懒构建的 filtered indirect draw buffers，cache key 就是 route mask；`Scene::setGeometryInstanceRenderRoute()` 现在会清掉这份 cache，避免脚本 override 后还沿用旧 draw list。
- `RayMarchingDirectAOPass` 新增 `instanceRouteMask` 属性，`RayMarchingTraversal.slang` 会在 DDA/mipmap/conservative traversal 的命中阶段检查 dominant instance route；当命中 `MeshOnly` voxel 时会继续穿透，不再为该命中做 voxel 正式 shading/output。
- 当前 voxel selective execution 仍然不是 route-aware `blockMap`/cache layout：如果一个 coarse block 里只有 `MeshOnly` voxel，ray march 仍会进入该 block 再逐体素跳过，所以 residual traversal cost 还在；本阶段的完成点是“停止正式出图”，不是“voxel block cost 归零”。
- `scripts\Voxelization_HybridMeshVoxel.py` 只在 `render_graph_hybrid()` 上挂 selective execution mask：
  `GBufferRaster.instanceRouteMask = Blend|MeshOnly`
  `RayMarchingDirectAOPass.instanceRouteMask = Blend|VoxelOnly`
  `render_graph_mesh_view()` 故意保持全场景未过滤，方便继续做 mesh debug/route debug。
- Phase4 的 `HybridBlendMaskPass` / `HybridCompositePass` correctness 逻辑没有回头重做；`ObjectMismatch`、`DepthMismatch` 和 existing route/depth/confidence 收口仍保持原样。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`

## 验证与证据

- 构建通过：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target GBuffer HybridVoxelMesh Voxelization Mogwai`
- hybrid smoke 已完成：
  启动 `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
  窗口截图 `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase5\hybrid_smoke_window.png`
- mainline smoke 已完成：
  启动 `E:\GraduateDesign\Falcor_Cp\run_DirectAO.bat`
  窗口截图 `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase5\mainline_smoke_window.png`
- 本轮没有补 pre/post Phase5 的正式 profile 对比；当前 handoff 只声明结构性 selective execution 已接入并完成窗口级 smoke。若要继续收口性能，请在此基线上补 pass/GPU profile，而不是回退到 composite-only discard。

## 后续继续时优先看

- 如果 `VoxelOnly` 物体又重新出现在 mesh 正式链里，先查 `GBufferRaster.instanceRouteMask` 是否仍由 hybrid graph 传入，以及 `Scene::setGeometryInstanceRenderRoute()` 是否还会清 filtered draw cache。
- 如果 `MeshOnly` 物体又重新被 voxel 正式链着色，先查 `RayMarchingTraversal.slang` 的 `isAcceptedVoxelOffset()` 是否还在所有 DDA/mipmap/conservative 命中点生效。
- 如果 profiling 发现 voxel cost 仍高，优先考虑 route-aware block occupancy 或 route-specific cache，而不是把 Phase5 退化成 screen-space discard/composite-only 单路显示。
