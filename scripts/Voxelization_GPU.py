import falcor

def render_graph_Pass():
    g = RenderGraph("Voxelization")

    voxel_pass = createPass("VoxelizationPass_GPU")
    read_pass = createPass("ReadVoxelPass")
    marching_pass = createPass("RayMarchingPass")
    accumulate_pass = createPass("AccumulatePass", {"enabled": True, "precisionMode": "Single"})

    g.addPass(voxel_pass,"VoxelizationPass")
    g.addPass(read_pass,"ReadVoxelPass")
    g.addPass(marching_pass,"RayMarchingPass")
    g.addPass(accumulate_pass,"AccumulatePass")

    g.addEdge("VoxelizationPass.dummy","ReadVoxelPass.dummy")
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
