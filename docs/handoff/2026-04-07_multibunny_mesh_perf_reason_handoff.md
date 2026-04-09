# MultiBunny Mesh Perf Reason Handoff

## 模块职责

解释 `run_HybridMeshVoxel.bat mesh` 在 `MultiBunny` 场景下为什么仍然很快，并收敛出在不改变当前光照模型前提下、如何更合理地把 mesh 参考路径变慢以便和 voxel 路径对比。

## 结论

- `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
  - `mesh` 参数会切到 `Voxelization_MultiBunny_MeshRoute.py`，不是 hybrid graph 的 `MeshOnly` debug view。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
  - 固定 `HYBRID_OUTPUT_MODE=meshview`、`HYBRID_FORCE_ALL_ROUTE=MeshOnly`，因此实际进入的是独立 mesh graph。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - `meshview` 会走 `render_graph_mesh_view()`，只保留 `MeshGBuffer -> MeshStyleDirectAOPass -> ToneMapper`。
  - 真正的 hybrid graph 仍会同时接上 mesh 与 voxel 正式链，`MeshOnly` / `VoxelOnly` 只是 composite 输出视图。
- `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
  - 当前场景只有 `5x5=25` 只 Bunny，且全部复用同一个 `bunnyGeometry`。
- `E:\GraduateDesign\Falcor_Cp\Scene\BoxBunny\Bunny.obj`
  - 实测约 `74,598` 个三角形，所以当前总量约 `1.86M` triangles；对现代 GPU 的纯 raster GBuffer 来说并不重。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
  - mesh 路径先做 depth prepass，再做 GBuffer pass。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
  - 光照在 fullscreen pass 里基于 GBuffer 计算，并且只对可见像素做 direct/AO；这也是它对“源三角面很多”不太敏感的主因。

## 建议

- 若目标是“不改光照模型，只让 mesh 更慢”，优先做：
  - 提高 framebuffer 分辨率。
  - 提高 `MultiBunny` 实例密度或相机过绘率。
  - 单独实现一个 forward reference pass，把当前 BRDF/visibility/AO 逻辑搬进 raster pixel shader。
- 不建议把“在 hybrid 里仍然跑 voxel 正式链，只看 mesh 输出”当成主对比口径；这会混入无关执行成本。

## 后续优先看

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
