import falcor

def render_graph_RasterPass():
    g = RenderGraph("Raster")

    GbufferPass = createPass("GBufferRaster", {
    "outputSizeSelection": "Default",
    })
    RasterPass = createPass("MyRasterPass")

    g.addPass(GbufferPass,"GBuffer")
    g.addPass(RasterPass, "MyRasterPass")

    g.addEdge("GBuffer.depth", "MyRasterPass.depth")
    g.addEdge("GBuffer.normW", "MyRasterPass.normal")
    g.addEdge("GBuffer.posW", "MyRasterPass.posW")
    g.addEdge("GBuffer.diffuseOpacity", "MyRasterPass.diffuseOpacity")
    g.addEdge("GBuffer.specRough", "MyRasterPass.specRough")
    g.addEdge("GBuffer.emissive", "MyRasterPass.emissive")
    g.addEdge("GBuffer.viewW", "MyRasterPass.viewW")
    g.addEdge("GBuffer.mtlData", "MyRasterPass.mtlData")

    g.markOutput("MyRasterPass.color")
    return g

RasterGraph = render_graph_RasterPass()
try: m.addGraph(RasterGraph)
except NameError: None
