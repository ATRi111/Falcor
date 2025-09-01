import falcor

def render_graph_RasterPass():
    g = RenderGraph("RiLoD")
    
    imposter_count = 6

    forward_pass = createPass("ForwardMappingPass", {
    "impostorCount": imposter_count,
    })
    g.addPass(forward_pass,"ForwardPass")
    for i in range(imposter_count):
        impostor_pass = createPass("ImpostorPass", {
        "viewpointIndex": i+1,
        })
        g.addPass(impostor_pass, f"ImpostorPass{i}")
        g.addEdge(f"ImpostorPass{i}.packedNDO",f"ForwardPass.packedNDO{i}")
        g.addEdge(f"ImpostorPass{i}.packedMCR",f"ForwardPass.packedMCR{i}")
        g.addEdge(f"ImpostorPass{i}.invVP",f"ForwardPass.invVP{i}")

    filter_pass = createPass("FilterPass")
    g.addPass(filter_pass,"FilterPass")
    g.addEdge("ForwardPass.mappedNDO","FilterPass.mappedNDO")
    g.addEdge("ForwardPass.mappedMCR","FilterPass.mappedMCR")

    reshading_pass = createPass("ReshadingPass")
    g.addPass(reshading_pass,"ReshadingPass")
    
    g.addEdge("FilterPass.filteredNDO","ReshadingPass.filteredNDO")
    g.addEdge("FilterPass.filteredMCR","ReshadingPass.filteredMCR")

    g.markOutput("ReshadingPass.color")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
