add_plugin(Voxelization)

target_sources(Voxelization PRIVATE
    VoxelGrid.slang
    Ellipsoid.slang
    ABSDF.slang
    Projection.slang
    ConvexHull.slang

    VoxelizationUtility.h
    MaterialUtility.h

    VoxelizationBase.h
    VoxelizationBase.cpp

    VoxelizationPass.cpp
    VoxelizationPass.h
    Voxelization.cs.slang

    RayMarchingPass.cpp
    RayMarchingPass.h
    RayMarching.ps.slang
    
    LoadMeshPass.cpp
    LoadMeshPass.h
    LoadMesh.cs.slang

    Image.h
    ImageLoader.cpp
    ImageLoader.h
    MeshSampler.h
    ReadVoxelPass.cpp
    ReadVoxelPass.h

    QuickHull/Structs/Mesh.hpp
    QuickHull/Structs/Plane.hpp
    QuickHull/Structs/Pool.hpp
    QuickHull/Structs/Ray.hpp
    QuickHull/Structs/Vector3.hpp
    QuickHull/Structs/VertexDataSource.hpp
    QuickHull/QuickHull.cpp
    QuickHull/ConvexHull.hpp
    QuickHull/HalfEdgeMesh.hpp
    QuickHull/MathUtils.hpp
    QuickHull/QuickHull.hpp

)
target_copy_shaders(Voxelization RenderPasses/Voxelization)
target_source_group(Voxelization "RenderPasses")
