import falcor

def render_graph_RasterPass():
    g = RenderGraph("Voxelization")

    voxel_pass = createPass("VoxelizationPass")
    marching_pass = createPass("RayMarchingPass")

    g.addPass(voxel_pass,"VoxelizationPass")
    g.addPass(marching_pass,"RayMarchingPass")

    g.addEdge("VoxelizationPass.diffuse","RayMarchingPass.diffuse")
    g.addEdge("VoxelizationPass.ellipsoids","RayMarchingPass.ellipsoids")

    g.markOutput("RayMarchingPass.color")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
