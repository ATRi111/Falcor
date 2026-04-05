add_plugin(HybridVoxelMesh)

target_sources(HybridVoxelMesh PRIVATE
    HybridMeshDebugPass.cpp
    HybridMeshDebugPass.h
    HybridMeshDebugPass.ps.slang
)

target_copy_shaders(HybridVoxelMesh RenderPasses/HybridVoxelMesh)
target_source_group(HybridVoxelMesh "RenderPasses")
