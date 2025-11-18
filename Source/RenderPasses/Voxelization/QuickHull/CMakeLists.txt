add_library(QuickHull STATIC
    Structs/Mesh.hpp
    Structs/Plane.hpp
    Structs/Pool.hpp
    Structs/Ray.hpp
    Structs/Vector3.hpp
    Structs/VertexDataSource.hpp

    QuickHull.cpp
    ConvexHull.hpp
    HalfEdgeMesh.hpp
    MathUtils.hpp
    QuickHull.hpp
)
target_include_directories(QuickHull PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})