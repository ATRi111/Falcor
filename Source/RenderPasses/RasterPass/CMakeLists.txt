add_plugin(RasterPass)

target_sources(RasterPass PRIVATE
    MyRasterPass.cpp
    MyRasterPass.h
    MyRasterPass.ps.slang
    MyRasterSharedTypes.slang
)

target_copy_shaders(RasterPass RenderPasses/RasterPass)
target_source_group(RasterPass "RenderPasses")
