import falcor
import os
import re


def env_bool(name, default):
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value.lower() not in ("0", "false", "off", "no")


def env_int(name, default):
    value = os.environ.get(name)
    return int(value) if value not in (None, "") else default

def resolve_voxel_backend():
    backend = os.environ.get("DIRECTAO_VOXELIZATION_BACKEND", "CPU").strip().upper()
    return backend if backend in ("CPU", "GPU") else "CPU"

CACHE_NAME_RE = re.compile(r"^(?P<prefix>.+)_\((?P<x>\d+), (?P<y>\d+), (?P<z>\d+)\)_(?P<sample>\d+)\.bin_(?P<backend>CPU|GPU)$", re.IGNORECASE)


def list_scene_cache_infos(scene_name_hint=""):
    resource_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "resource")
    infos = []
    if not os.path.isdir(resource_dir):
        return resource_dir, infos

    hint = scene_name_hint.lower()
    for filename in sorted(os.listdir(resource_dir)):
        match = CACHE_NAME_RE.match(filename)
        if not match:
            continue
        lower = filename.lower()
        if hint and hint not in lower:
            continue
        infos.append(
            {
                "filename": filename,
                "path": os.path.join(resource_dir, filename),
                "prefix": match.group("prefix"),
                "voxel_count": (
                    int(match.group("x")),
                    int(match.group("y")),
                    int(match.group("z")),
                ),
                "sample_frequency": int(match.group("sample")),
                "backend": match.group("backend").upper(),
            }
        )

    return resource_dir, infos


def choose_cache_plan(scene_name_hint="", backend="CPU", allow_fallback=False):
    resource_dir, infos = list_scene_cache_infos(scene_name_hint)
    preferred = next((info for info in infos if info["backend"] == backend), None)
    reference = preferred or (infos[0] if infos else None)

    inferred_resolution = None
    inferred_sample_frequency = None
    desired_path = ""
    desired_exists = False

    if reference:
        inferred_resolution = max(reference["voxel_count"])
        inferred_sample_frequency = reference["sample_frequency"]
        desired_filename = (
            f'{reference["prefix"]}_({reference["voxel_count"][0]}, {reference["voxel_count"][1]}, {reference["voxel_count"][2]})_'
            f'{reference["sample_frequency"]}.bin_{backend}'
        )
        desired_path = os.path.join(resource_dir, desired_filename)
        desired_exists = os.path.exists(desired_path)

    bin_file = ""
    if preferred:
        bin_file = preferred["path"]
    elif backend == "CPU" and desired_path:
        bin_file = desired_path
    elif allow_fallback and reference:
        bin_file = reference["path"]

    return {
        "bin_file": bin_file,
        "desired_path": desired_path,
        "desired_exists": desired_exists,
        "voxel_resolution": inferred_resolution,
        "sample_frequency": inferred_sample_frequency,
    }

def resolve_scene_hint():
    # `--scene` 传入的场景有时会在脚本执行后才真正绑定到 `m.scene`，
    # 先读 batch 明确传入的 hint，避免 CornellBox 启动时回退到 Arcade cache。
    for key in ("DIRECTAO_SCENE_PATH", "DIRECTAO_SCENE_HINT"):
        value = os.environ.get(key, "").strip()
        if value:
            return os.path.basename(value).split(".")[0]

    try:
        if m.scene:
            return os.path.basename(str(m.scene.path)).split(".")[0]
    except Exception:
        pass

    return ""

def render_graph_Pass():
    scene_hint = resolve_scene_hint()
    voxel_backend = resolve_voxel_backend()
    allow_cache_fallback = env_bool("DIRECTAO_ALLOW_CACHE_FALLBACK", False)
    cache_plan = choose_cache_plan(scene_hint, voxel_backend, allow_cache_fallback)
    bin_file = cache_plan["bin_file"]
    draw_mode = env_int("DIRECTAO_DRAW_MODE", 0)
    output_resolution = env_int("DIRECTAO_OUTPUT_RESOLUTION", 0)
    check_ellipsoid = env_bool("DIRECTAO_CHECK_ELLIPSOID", True)
    check_visibility = env_bool("DIRECTAO_CHECK_VISIBILITY", True)
    check_coverage = env_bool("DIRECTAO_CHECK_COVERAGE", True)
    use_mipmap = env_bool("DIRECTAO_USE_MIPMAP", True)
    render_background = env_bool("DIRECTAO_RENDER_BACKGROUND", True)
    transmittance_threshold = float(os.environ.get("DIRECTAO_TRANSMITTANCE_THRESHOLD", "5.0"))
    ao_enabled = env_bool("DIRECTAO_AO_ENABLED", True)
    ao_strength = float(os.environ.get("DIRECTAO_AO_STRENGTH", "0.55"))
    ao_radius = float(os.environ.get("DIRECTAO_AO_RADIUS", "6.0"))
    ao_step_count = env_int("DIRECTAO_AO_STEP_COUNT", 3)
    ao_direction_set = env_int("DIRECTAO_AO_DIRECTION_SET", 6)
    ao_contact_strength = float(os.environ.get("DIRECTAO_AO_CONTACT_STRENGTH", "0.75"))
    ao_use_stable_rotation = env_bool("DIRECTAO_AO_USE_STABLE_ROTATION", True)
    voxel_pass_name = "VoxelizationPass_CPU" if voxel_backend == "CPU" else "VoxelizationPass_GPU"
    voxel_pass_props = {}
    if voxel_backend == "CPU":
        cpu_voxel_resolution = env_int("DIRECTAO_CPU_VOXEL_RESOLUTION", cache_plan["voxel_resolution"] or 128)
        cpu_sample_frequency = env_int("DIRECTAO_CPU_SAMPLE_FREQUENCY", cache_plan["sample_frequency"] or 256)
        voxel_pass_props = {
            "sceneName": "Auto",
            "voxelResolution": cpu_voxel_resolution,
            "sampleFrequency": cpu_sample_frequency,
            "polygonPerFrame": env_int("DIRECTAO_CPU_POLYGON_PER_FRAME", 256000),
            "lerpNormal": env_bool("DIRECTAO_CPU_LERP_NORMAL", False),
            "autoGenerate": env_bool(
                "DIRECTAO_CPU_AUTO_GENERATE",
                bool(cache_plan["desired_path"]) and not cache_plan["desired_exists"],
            ),
        }
    print("[MainlineDirectAO] scene hint:", scene_hint if scene_hint else "<empty>")
    print("[MainlineDirectAO] voxel backend:", voxel_backend)
    print("[MainlineDirectAO] voxel cache:", bin_file if bin_file else "<none>")

    g = RenderGraph("VoxelizationMainlineDirectAO")

    voxel_pass = createPass(voxel_pass_name, voxel_pass_props)
    read_pass = createPass("ReadVoxelPass", {"binFile": bin_file} if bin_file else {})
    marching_pass = createPass(
        "RayMarchingDirectAOPass",
        {
            "drawMode": draw_mode,
            "outputResolution": output_resolution,
            "checkEllipsoid": check_ellipsoid,
            "checkVisibility": check_visibility,
            "checkCoverage": check_coverage,
            "useMipmap": use_mipmap,
            "renderBackground": render_background,
            "transmittanceThreshold": transmittance_threshold,
            "aoEnabled": ao_enabled,
            "aoStrength": ao_strength,
            "aoRadius": ao_radius,
            "aoStepCount": ao_step_count,
            "aoDirectionSet": ao_direction_set,
            "aoContactStrength": ao_contact_strength,
            "aoUseStableRotation": ao_use_stable_rotation,
        },
    )
    tone_mapper = createPass("ToneMapper", {"autoExposure": False, "exposureCompensation": 0.0})

    g.addPass(voxel_pass, "VoxelizationPass")
    g.addPass(read_pass, "ReadVoxelPass")
    g.addPass(marching_pass, "RayMarchingDirectAOPass")
    g.addPass(tone_mapper, "ToneMapper")

    g.addEdge("VoxelizationPass.dummy", "ReadVoxelPass.dummy")
    g.addEdge("ReadVoxelPass.vBuffer", "RayMarchingDirectAOPass.vBuffer")
    g.addEdge("ReadVoxelPass.gBuffer", "RayMarchingDirectAOPass.gBuffer")
    g.addEdge("ReadVoxelPass.pBuffer", "RayMarchingDirectAOPass.pBuffer")
    g.addEdge("ReadVoxelPass.blockMap", "RayMarchingDirectAOPass.blockMap")

    g.addEdge("RayMarchingDirectAOPass.color", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")

    return g


Graph = render_graph_Pass()
try:
    m.addGraph(Graph)
except NameError:
    pass
