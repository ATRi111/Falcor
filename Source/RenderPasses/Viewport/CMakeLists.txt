add_plugin(Viewport)

target_sources(Viewport PRIVATE
    RenderToViewportPass.h
    RenderToViewportPass.cpp
    RenderToViewport.ps.slang
)

target_copy_shaders(Viewport RenderPasses/Viewport)

target_source_group(Viewport "RenderPasses")
