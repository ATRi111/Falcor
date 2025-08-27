import falcor

def render_graph_RasterPass():
    g = RenderGraph("Imposter")
    
    num_passes = 3
    
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
    
    for i in range(num_passes):
        pass_name = f"ImpostorPass{i}"
        params = pass_params[i]
        
        impostor_pass = createPass("ImpostorPass", params)
        
        g.addPass(impostor_pass, pass_name)
        
        g.markOutput(f"{pass_name}.packedFloats")
    
    return g

Graph = render_graph_RasterPass()
try: 
    m.addGraph(Graph)
except NameError: 
    pass
