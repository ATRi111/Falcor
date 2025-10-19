add_plugin(Voxelization)

target_sources(Voxelization PRIVATE
    VoxelizationShared.slang
    VoxelizationBase.h
    VoxelizationBase.cpp

    VoxelizationPass.cpp
    VoxelizationPass.h
    Voxelization.cs.slang

    RayMarchingPass.cpp
    RayMarchingPass.h
    RayMarching.ps.slang
)
target_copy_shaders(Voxelization RenderPasses/Voxelization)
target_source_group(Voxelization "RenderPasses")
