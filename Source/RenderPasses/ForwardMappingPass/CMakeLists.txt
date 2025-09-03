add_plugin(ForwardMappingPass)

target_sources(ForwardMappingPass PRIVATE
    ForwardMappingPass.cpp
    ForwardMappingPass.h
    ForwardMapping.cs.slang
    ForwardDepth.cs.slang
)

target_source_group(ForwardMappingPass "RenderPasses")
