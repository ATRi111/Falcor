import falcor

def render_graph_Pass():
    g = RenderGraph("Voxelization")

    voxel_pass = createPass("VoxelizationPass_CPU")
    read_pass = createPass("ReadVoxelPass")
    marching_pass = createPass("RayMarchingPass")
    accumulate_pass = createPass("AccumulatePass", {"enabled": True, "precisionMode": "Single",'maxFrameCount': 1024})
    ToneMapper = createPass("ToneMapper", {'autoExposure': False, 'exposureCompensation': 0.0})

    g.addPass(voxel_pass,"VoxelizationPass")
    g.addPass(read_pass,"ReadVoxelPass")
    g.addPass(marching_pass,"RayMarchingPass")
    g.addPass(accumulate_pass,"AccumulatePass")
    g.addPass(ToneMapper, "ToneMapper")

    g.addEdge("VoxelizationPass.dummy","ReadVoxelPass.dummy")
    g.addEdge("ReadVoxelPass.vBuffer","RayMarchingPass.vBuffer")
    g.addEdge("ReadVoxelPass.gBuffer","RayMarchingPass.gBuffer")

    g.addEdge("RayMarchingPass.color","AccumulatePass.input")
    g.addEdge("AccumulatePass.output", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")

    return g

Graph = render_graph_Pass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
