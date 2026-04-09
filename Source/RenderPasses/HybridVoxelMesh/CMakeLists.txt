add_plugin(HybridVoxelMesh)

target_sources(HybridVoxelMesh PRIVATE
    HybridMeshDebugPass.cpp
    HybridMeshDebugPass.h
    HybridMeshDebugPass.ps.slang
    HybridCompositePass.cpp
    HybridCompositePass.h
    HybridCompositePass.ps.slang
    MeshStyleDirectAOPass.cpp
    MeshStyleDirectAOPass.h
    MeshStyleDirectAOPass.ps.slang
)

target_copy_shaders(HybridVoxelMesh RenderPasses/HybridVoxelMesh)
target_source_group(HybridVoxelMesh "RenderPasses")
