import falcor
import os


def env_bool(name, default):
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value.lower() not in ("0", "false", "off", "no")


def env_int(name, default):
    value = os.environ.get(name)
    return int(value) if value not in (None, "") else default


def env_float(name, default):
    value = os.environ.get(name)
    return float(value) if value not in (None, "") else default


def parse_float3(value):
    if value in (None, ""):
        return None

    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 3:
        raise ValueError(f"Expected three comma-separated values, got: {value}")
    return tuple(float(part) for part in parts)


ARCADE_REFERENCE_VIEWS = {
    "near": {
        "position": (-0.811894, 1.575547, 1.825012),
        "target": (-0.370011, 1.218823, 1.001915),
        "up": (-0.376237, 0.634521, 0.675103),
        "focalLength": 21.0,
    },
    "mid": {
        "position": (-1.143306, 1.843090, 2.442334),
        "target": (-0.701423, 1.486366, 1.619238),
        "up": (-0.376237, 0.634521, 0.675103),
        "focalLength": 21.0,
    },
    "far": {
        "position": (-1.585189, 2.199814, 3.265431),
        "target": (-1.143306, 1.843090, 2.442334),
        "up": (-0.376237, 0.634521, 0.675103),
        "focalLength": 21.0,
    },
}


REFERENCE_VIEWS_BY_SCENE = {
    "arcade": ARCADE_REFERENCE_VIEWS,
}


def resolve_scene_hint():
    for key in ("HYBRID_SCENE_PATH", "HYBRID_SCENE_HINT"):
        value = os.environ.get(key, "").strip()
        if value:
            return os.path.basename(value).split(".")[0]

    try:
        if m.scene:
            return os.path.basename(str(m.scene.path)).split(".")[0]
    except Exception:
        pass

    return ""


def resolve_reference_view(scene_hint, reference_view_name):
    if not reference_view_name:
        return None

    presets = REFERENCE_VIEWS_BY_SCENE.get(scene_hint.lower())
    if not presets:
        return None

    return presets.get(reference_view_name.lower())


def resolve_camera_plan(scene_hint):
    reference_view_name = os.environ.get("HYBRID_REFERENCE_VIEW", "").strip()
    preset = resolve_reference_view(scene_hint, reference_view_name)
    position = parse_float3(os.environ.get("HYBRID_CAMERA_POSITION"))
    target = parse_float3(os.environ.get("HYBRID_CAMERA_TARGET"))
    up = parse_float3(os.environ.get("HYBRID_CAMERA_UP"))
    focal_length = env_float("HYBRID_CAMERA_FOCAL_LENGTH", 0.0)

    if preset:
        position = position or preset["position"]
        target = target or preset["target"]
        up = up or preset["up"]
        if focal_length <= 0.0:
            focal_length = preset["focalLength"]

    if position is None and target is None and up is None and focal_length <= 0.0:
        return None

    return {
        "reference_view": reference_view_name,
        "position": position,
        "target": target,
        "up": up,
        "focal_length": focal_length,
    }


def apply_renderer_overrides(camera_plan):
    hide_ui = env_bool("HYBRID_HIDE_UI", False)
    framebuffer_width = env_int("HYBRID_FRAMEBUFFER_WIDTH", 0)
    framebuffer_height = env_int("HYBRID_FRAMEBUFFER_HEIGHT", 0)

    if hide_ui:
        m.ui = False

    if framebuffer_width > 0 and framebuffer_height > 0:
        m.resizeFrameBuffer(framebuffer_width, framebuffer_height)

    if not camera_plan:
        return

    camera_applied = {"done": False}

    def apply_camera_once(scene, current_time):
        if camera_applied["done"] or scene is None or scene.camera is None:
            return

        camera = scene.camera
        if camera_plan["position"] is not None:
            camera.position = falcor.float3(*camera_plan["position"])
        if camera_plan["target"] is not None:
            camera.target = falcor.float3(*camera_plan["target"])
        if camera_plan["up"] is not None:
            camera.up = falcor.float3(*camera_plan["up"])
        if camera_plan["focal_length"] > 0.0:
            camera.focalLength = camera_plan["focal_length"]

        camera_applied["done"] = True
        m.sceneUpdateCallback = None
        print(
            "[HybridMeshVoxel] camera:",
            camera_plan["reference_view"] if camera_plan["reference_view"] else "<explicit>",
        )

    m.sceneUpdateCallback = apply_camera_once


def render_graph_phase1():
    scene_hint = resolve_scene_hint()
    camera_plan = resolve_camera_plan(scene_hint)
    view_mode = os.environ.get("HYBRID_MESH_VIEW_MODE", "DirectOnly").strip() or "DirectOnly"
    depth_range = env_float("HYBRID_MESH_DEPTH_RANGE", 12.0)
    shadow_bias = env_float("HYBRID_MESH_SHADOW_BIAS", 0.001)
    render_background = env_bool("HYBRID_MESH_RENDER_BACKGROUND", True)

    print("[HybridMeshVoxel] scene hint:", scene_hint if scene_hint else "<empty>")
    print("[HybridMeshVoxel] mesh view mode:", view_mode)
    if os.environ.get("HYBRID_REFERENCE_VIEW", "").strip():
        print("[HybridMeshVoxel] reference view:", os.environ["HYBRID_REFERENCE_VIEW"].strip())

    g = RenderGraph("VoxelizationHybridMeshVoxelPhase1")

    mesh_gbuffer = createPass(
        "GBufferRaster",
        {
            "outputSize": "Default",
            "samplePattern": "Center",
            "useAlphaTest": True,
            "adjustShadingNormals": True,
        },
    )
    mesh_debug = createPass(
        "HybridMeshDebugPass",
        {
            "viewMode": view_mode,
            "depthRange": depth_range,
            "shadowBias": shadow_bias,
            "renderBackground": render_background,
        },
    )
    tone_mapper = createPass("ToneMapper", {"autoExposure": False, "exposureCompensation": 0.0})

    g.addPass(mesh_gbuffer, "MeshGBuffer")
    g.addPass(mesh_debug, "HybridMeshDebugPass")
    g.addPass(tone_mapper, "ToneMapper")

    g.addEdge("MeshGBuffer.posW", "HybridMeshDebugPass.posW")
    g.addEdge("MeshGBuffer.normW", "HybridMeshDebugPass.normW")
    g.addEdge("MeshGBuffer.faceNormalW", "HybridMeshDebugPass.faceNormalW")
    g.addEdge("MeshGBuffer.viewW", "HybridMeshDebugPass.viewW")
    g.addEdge("MeshGBuffer.diffuseOpacity", "HybridMeshDebugPass.diffuseOpacity")
    g.addEdge("MeshGBuffer.specRough", "HybridMeshDebugPass.specRough")
    g.addEdge("MeshGBuffer.emissive", "HybridMeshDebugPass.emissive")
    g.addEdge("HybridMeshDebugPass.color", "ToneMapper.src")

    g.markOutput("ToneMapper.dst")

    apply_renderer_overrides(camera_plan)
    return g


Graph = render_graph_phase1()
try:
    m.addGraph(Graph)
except NameError:
    pass
