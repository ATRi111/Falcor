import falcor

def render_graph_RasterPass():
    g = RenderGraph("Voxelization")

    voxel_pass = createPass("VoxelizationPass")
    marching_pass = createPass("RayMarchingPass")

    g.addPass(voxel_pass,"VoxelizationPass")
    g.addPass(marching_pass,"RayMarchingPass")

    g.addEdge("VoxelizationPass.OM","RayMarchingPass.OM")
    g.addEdge("VoxelizationPass.mipOM","RayMarchingPass.mipOM")
    g.addEdge("VoxelizationPass.gridData","RayMarchingPass.gridData")

    g.markOutput("RayMarchingPass.color")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
