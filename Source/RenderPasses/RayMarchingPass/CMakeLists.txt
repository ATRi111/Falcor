add_plugin(RayMarchingPass)

target_sources(RayMarchingPass PRIVATE
    RayMarchingPass.cpp
    RayMarchingPass.h
    RayMarching.ps.slang
)

target_source_group(RayMarchingPass "RenderPasses")
