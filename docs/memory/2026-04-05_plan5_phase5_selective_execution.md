# 2026-04-05 Plan5 Phase5 Selective Execution

- Phase5 mesh selective execution should live at `GBufferRaster -> Scene::rasterize()`, not in `MeshStyleDirectAOPass`; the current raster indirect args are one triangle-mesh instance per record, so a route-aware draw-arg filter can skip `VoxelOnly` instances before depth/GBuffer shading instead of paying raster cost and discarding later.
- Current voxel selective execution is hit-level, not block-level: `RayMarchingTraversal.slang` now treats `MeshOnly` dominant-instance voxels as transparent and keeps marching, which removes MeshOnly formal shading/output but still descends into coarse `blockMap` regions because the cache occupancy is not route-aware.
- Keep the route masks hybrid-only in `scripts\Voxelization_HybridMeshVoxel.py`; `render_graph_mesh_view()` stays unfiltered for debug, while `render_graph_hybrid()` drives `GBufferRaster.instanceRouteMask = Blend|MeshOnly` and `RayMarchingDirectAOPass.instanceRouteMask = Blend|VoxelOnly`.
