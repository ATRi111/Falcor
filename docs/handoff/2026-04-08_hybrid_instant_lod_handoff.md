# Hybrid Instant LOD Handoff

## 模块职责

- `scripts/Voxelization_HybridMeshVoxel.py` 现在负责 hybrid LOD 的正式执行策略：把 scene authoring 的 `Blend` route 解析成传统瞬切的 `MeshOnly / VoxelOnly`，并决定默认 graph 是 hybrid、mesh 还是 voxel。
- mesh 正式链依赖 `GBufferRaster.instanceRouteMask` 做 route 过滤。
- voxel 正式链依赖 `VoxelRoutePreparePass` 生成 route-aware block map，再由 `RayMarchingDirectAOPass` / `RayMarchingTraversal.slang` 读取，避免 `MeshOnly` 物体继续激活 voxel traversal。
- `HybridCompositePass` 现在只保留 source/debug composite 职责，不再承担 blend 权重合成。

## 优先查看

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelRoutePreparePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelRoutePrepare.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`

## 本次收口

- 正式 hybrid 路径已移除 `HybridBlendMaskPass`，插件和 CMake 不再编译它。
- `Blend` 不再作为脚本 override / force route 的合法输入；它只保留为 scene authoring 默认态，并在运行时被 resolve。
- `HYBRID_FORCE_ALL_ROUTE=MeshOnly/VoxelOnly` 配合默认 `Composite` 输出时，会直接收成纯 `mesh` / 纯 `voxel` graph。

## 验证

- Release 构建通过：
  - `Voxelization`
  - `HybridVoxelMesh`
  - `Mogwai`
- 短时运行通过：
  - `run_VoxelBunny_Blend.bat`
  - `run_DirectAO.bat`
- 运行日志在：
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\instant_lod_smoke_stdout.log`
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\direct_ao_smoke_stdout.log`
