import falcor

def render_graph_RasterPass():
    g = RenderGraph("Voxelization")

    load_pass = createPass("LoadMeshPass")
    g.addPass(load_pass,"LoadMeshPass")

    read_pass = createPass("ReadVoxelPass")
    marching_pass = createPass("RayMarchingPass")

    g.addPass(read_pass,"ReadVoxelPass")
    g.addPass(marching_pass,"RayMarchingPass")

    g.addEdge("LoadMeshPass.dummy","ReadVoxelPass.dummy")
    g.addEdge("ReadVoxelPass.diffuse","RayMarchingPass.diffuse")
    g.addEdge("ReadVoxelPass.specular","RayMarchingPass.specular")
    g.addEdge("ReadVoxelPass.ellipsoids","RayMarchingPass.ellipsoids")
    g.addEdge("ReadVoxelPass.NDFLobes","RayMarchingPass.NDFLobes")

    g.markOutput("RayMarchingPass.color")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
