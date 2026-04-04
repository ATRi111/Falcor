import os


def find_bin_file(scene_name_hint=""):
    resource_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "resource")
    if not os.path.isdir(resource_dir):
        return ""

    files = sorted(os.listdir(resource_dir))
    if scene_name_hint:
        hint = scene_name_hint.lower()
        for filename in files:
            if hint in filename.lower():
                return os.path.join(resource_dir, filename)

    return os.path.join(resource_dir, files[0]) if files else ""


def build_graph(draw_mode=1, output_resolution=256):
    scene_hint = ""
    try:
        if m.scene:
            scene_hint = os.path.basename(str(m.scene.path)).split(".")[0]
    except Exception:
        pass

    bin_file = find_bin_file(scene_hint)

    g = RenderGraph("VoxelizationMainlineDirectAO_Capture")

    voxel_pass = createPass("VoxelizationPass_GPU")
    read_pass = createPass("ReadVoxelPass", {"binFile": bin_file} if bin_file else {})
    marching_pass = createPass(
        "RayMarchingDirectAOPass",
        {
            "drawMode": draw_mode,
            "outputResolution": output_resolution,
            "renderBackground": True,
            "useMipmap": True,
            "checkEllipsoid": True,
            "checkVisibility": True,
            "checkCoverage": True,
        },
    )
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


draw_mode = int(os.environ.get("DIRECTAO_DRAW_MODE", "1"))
output_resolution = int(os.environ.get("DIRECTAO_OUTPUT_RESOLUTION", "256"))
base_filename = os.environ.get("DIRECTAO_BASE_FILENAME", "mainline_directao")

Graph = build_graph(draw_mode=draw_mode, output_resolution=output_resolution)
m.addGraph(Graph)
m.setActiveGraph(Graph)
m.ui = False
m.resizeFrameBuffer(512, 512)
m.clock.pause()
output_dir = r"E:\GraduateDesign\Falcor_Cp\.FORAGENT\captures"
os.makedirs(output_dir, exist_ok=True)
m.frameCapture.outputDir = output_dir
m.frameCapture.baseFilename = base_filename

for frame in range(4):
    m.clock.frame = frame
    m.renderFrame()

m.frameCapture.capture()
exit()
