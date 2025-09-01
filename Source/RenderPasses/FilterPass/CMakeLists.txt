add_plugin(FilterPass)

target_sources(FilterPass PRIVATE
    FilterPass.cpp
    FilterPass.h
    Filter.cs.slang
)

target_source_group(FilterPass "RenderPasses")
