import falcor

def render_graph_RasterPass():
    g = RenderGraph("RiLoD")
    
    imposter_count = 3
    
    pass_params = [
        # {
        #     "outputSizeSelection": "Default",
        #     "cameraPosition": [0.0, 3.0, 1.0],
        #     "cameraTarget": [0.0, 2.0, 1.0],
        #     "cameraUp": [0.0, 0.0, 1.0],
        #     "viewpointIndex": 1,
        # },
        {
            "outputSizeSelection": "Default",
            "cameraPosition": [-0.8, 3.0, 1.0],
            "cameraTarget": [-0.8, 2.0, 1.0],
            "cameraUp": [1.0, 0.0, 0.0],
            "viewpointIndex": 1,
        },
        {
            "outputSizeSelection": "Default",
            "cameraPosition": [-1.0, 1.2, 3.0],
            "cameraTarget": [-1.0, 1.2, 2.0],
            "cameraUp": [0.0, 1.0, 0.0],
            "viewpointIndex": 2,
        },
        {
            "outputSizeSelection": "Default",
            "cameraPosition": [-3.0, 1.2, 1.2],
            "cameraTarget": [-2.0, 1.2, 1.2],
            "cameraUp": [0.0, 1.0, 0.0],
            "viewpointIndex": 3,
        },
    ]

    forward_pass = createPass("ForwardMappingPass", {
    "impostorCount": imposter_count,
    })

    g.addPass(forward_pass,"ForwardPass")
    
    for i in range(imposter_count):
        
        impostor_pass = createPass("ImpostorPass", pass_params[i])
        
        g.addPass(impostor_pass, f"ImpostorPass{i}")
        g.addEdge(f"ImpostorPass{i}.packedNDO",f"ForwardPass.packedNDO{i}")
        g.addEdge(f"ImpostorPass{i}.packedMCR",f"ForwardPass.packedMCR{i}")
        g.addEdge(f"ImpostorPass{i}.invVP",f"ForwardPass.invVP{i}")
        
    g.markOutput(f"ForwardPass.worldNormal")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
