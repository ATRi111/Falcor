import falcor

def render_graph_RasterPass():
    g = RenderGraph("Voxelization")

    load_pass = createPass("LoadMeshPass")

    g.addPass(load_pass,"LoadMeshPass")

    g.markOutput("LoadMeshPass.color")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
