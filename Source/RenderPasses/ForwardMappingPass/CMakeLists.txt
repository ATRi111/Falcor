add_plugin(ForwardMappingPass)

target_sources(ForwardMappingPass PRIVATE
    ForwardMappingPass.cpp
    ForwardMappingPass.h
)

target_source_group(ForwardMappingPass "RenderPasses")
