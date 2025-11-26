import falcor

def render_graph_Pass():
    g = RenderGraph("Voxelization")

    load_pass = createPass("LoadMeshPass")
    read_pass = createPass("ReadVoxelPass")
    marching_pass = createPass("RayMarchingPass")
    accumulate_pass = createPass("AccumulatePass", {"enabled": False, "precisionMode": "Single"})

    g.addPass(load_pass,"LoadMeshPass")
    g.addPass(read_pass,"ReadVoxelPass")
    g.addPass(marching_pass,"RayMarchingPass")
    g.addPass(accumulate_pass,"AccumulatePass")

    g.addEdge("LoadMeshPass.dummy","ReadVoxelPass.dummy")
    g.addEdge("ReadVoxelPass.vBuffer","RayMarchingPass.vBuffer")
    g.addEdge("ReadVoxelPass.gBuffer","RayMarchingPass.gBuffer")

    g.addEdge("RayMarchingPass.color","AccumulatePass.input")
    g.markOutput("AccumulatePass.output")
    
    return g

Graph = render_graph_Pass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
