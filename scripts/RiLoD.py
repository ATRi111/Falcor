import falcor

def render_graph_RasterPass():
    g = RenderGraph("Imposter")
    
    imposter_count = 3
    
    pass_params = [
        {
            "outputSizeSelection": "Default",
            "cameraPosition": [0.0, 1.0, 5.0],
            "cameraTarget": [0.0, 1.0, 4.0],
            "cameraUp": [0.0, 1.0, 0.0],
            "viewpointIndex": 1,
        },
        {
            "outputSizeSelection": "Default",
            "cameraPosition": [-5.0, 1.0, 1.0],
            "cameraTarget": [-4.0, 1.0, 1.0],
            "cameraUp": [0.0, 1.0, 0.0],
            "viewpointIndex": 2,
        },
        {
            "outputSizeSelection": "Default",
            "cameraPosition": [0.0, 6.0, 1.0],
            "cameraTarget": [0.0, 5.0, 1.0],
            "cameraUp": [0.0, 1.0, -1.0],
            "viewpointIndex": 3,
        }
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
        g.addEdge(f"ImpostorPass{i}.viewpoint",f"ForwardPass.viewpoint{i}")
        
    g.markOutput(f"ForwardPass.mappedNDO")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
