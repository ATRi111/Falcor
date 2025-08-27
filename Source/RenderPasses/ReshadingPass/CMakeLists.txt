add_plugin(ReshadingPass)

target_sources(ReshadingPass PRIVATE
    ReshadingPass.cpp
    ReshadingPass.h
)

target_copy_shaders(ReshadingPass RenderPasses/ReshadingPass)
target_source_group(ReshadingPass "RenderPasses")
