import os
from pathlib import Path


def set_default_env(name, value):
    if not os.environ.get(name):
        os.environ[name] = value


repo_root = Path(__file__).resolve().parent.parent

set_default_env("HYBRID_REPO_ROOT", str(repo_root))
set_default_env("HYBRID_SCENE_PATH", str(repo_root / "Scene" / "MultiBunny.pyscene"))
set_default_env("HYBRID_SCENE_HINT", "MultiBunnySparseLerp")
set_default_env("HYBRID_CPU_SCENE_NAME", "MultiBunnySparseLerp")
set_default_env("HYBRID_VOXEL_CACHE_FILE", str(repo_root / "resource" / "MultiBunnySparseLerp_(128, 16, 128)_128.bin_CPU"))
set_default_env("HYBRID_FORCE_ALL_ROUTE", "Blend")
set_default_env("HYBRID_OUTPUT_MODE", "composite")
set_default_env("HYBRID_FRAMEBUFFER_WIDTH", "1600")
set_default_env("HYBRID_FRAMEBUFFER_HEIGHT", "900")
set_default_env("HYBRID_VOXELIZATION_BACKEND", "CPU")
set_default_env("HYBRID_CPU_VOXEL_RESOLUTION", "128")
set_default_env("HYBRID_CPU_SAMPLE_FREQUENCY", "128")
set_default_env("HYBRID_CPU_AUTO_GENERATE", "1")
set_default_env("HYBRID_CPU_LERP_NORMAL", "1")
set_default_env("HYBRID_BLEND_START_DISTANCE", "3.00")
set_default_env("HYBRID_BLEND_END_DISTANCE", "5.75")
set_default_env("HYBRID_BLEND_EXPONENT", "1.0")

base_script = Path(__file__).with_name("Voxelization_HybridMeshVoxel.py")
globals()["__file__"] = str(base_script)
exec(compile(base_script.read_text(encoding="utf-8"), str(base_script), "exec"), globals(), globals())
