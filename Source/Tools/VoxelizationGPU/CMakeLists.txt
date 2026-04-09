add_falcor_executable(VoxelizationGPU)

target_sources(VoxelizationGPU PRIVATE
    VoxelizationGPU.cpp
)

target_link_libraries(VoxelizationGPU PRIVATE args)
target_include_directories(VoxelizationGPU PRIVATE ${CMAKE_SOURCE_DIR}/Source)

get_property(falcor_plugin_targets GLOBAL PROPERTY FALCOR_PLUGIN_TARGETS)
if(falcor_plugin_targets)
    add_dependencies(VoxelizationGPU ${falcor_plugin_targets})
endif()
add_dependencies(VoxelizationGPU FalcorPython)

target_source_group(VoxelizationGPU "Tools")
