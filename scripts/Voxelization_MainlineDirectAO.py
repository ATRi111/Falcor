import falcor


def render_graph_Pass():
    g = RenderGraph("VoxelizationMainlineDirectAO")

    voxel_pass = createPass("VoxelizationPass_GPU")
    read_pass = createPass("ReadVoxelPass")
    marching_pass = createPass("RayMarchingDirectAOPass")
    viewport_pass = createPass("RenderToViewportPass")
    accumulate_pass = createPass("AccumulatePass", {"enabled": True, "autoReset": True, "precisionMode": "Single", "maxFrameCount": 1024})
    tone_mapper = createPass("ToneMapper", {"autoExposure": False, "exposureCompensation": 0.0})

    g.addPass(voxel_pass, "VoxelizationPass")
    g.addPass(read_pass, "ReadVoxelPass")
    g.addPass(marching_pass, "RayMarchingDirectAOPass")
    g.addPass(viewport_pass, "RenderToViewportPass")
    g.addPass(accumulate_pass, "AccumulatePass")
    g.addPass(tone_mapper, "ToneMapper")

    g.addEdge("VoxelizationPass.dummy", "ReadVoxelPass.dummy")
    g.addEdge("ReadVoxelPass.vBuffer", "RayMarchingDirectAOPass.vBuffer")
    g.addEdge("ReadVoxelPass.gBuffer", "RayMarchingDirectAOPass.gBuffer")
    g.addEdge("ReadVoxelPass.pBuffer", "RayMarchingDirectAOPass.pBuffer")
    g.addEdge("ReadVoxelPass.blockMap", "RayMarchingDirectAOPass.blockMap")

    g.addEdge("RayMarchingDirectAOPass.color", "RenderToViewportPass.input")
    g.addEdge("RenderToViewportPass.output", "AccumulatePass.input")
    g.addEdge("AccumulatePass.output", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")

    return g


Graph = render_graph_Pass()
try:
    m.addGraph(Graph)
except NameError:
    pass
