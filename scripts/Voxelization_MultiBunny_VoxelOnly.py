import os
from pathlib import Path


def set_default_env(name, value):
    if not os.environ.get(name):
        os.environ[name] = value


repo_root = Path(__file__).resolve().parent.parent

set_default_env("HYBRID_REPO_ROOT", str(repo_root))
set_default_env("HYBRID_SCENE_PATH", str(repo_root / "Scene" / "MultiMultiBunny.pyscene"))
set_default_env("HYBRID_SCENE_HINT", "MultiMultiBunny")
set_default_env("HYBRID_CPU_SCENE_NAME", "MultiMultiBunny")
set_default_env("HYBRID_VOXEL_CACHE_FILE", str(repo_root / "resource" / "MultiMultiBunny_(512, 41, 499)_512.bin_CPU"))
set_default_env("HYBRID_FORCE_ALL_ROUTE", "VoxelOnly")
set_default_env("HYBRID_PIPELINE_MODE", "voxel")
set_default_env("HYBRID_OUTPUT_MODE", "voxelonly")
set_default_env("HYBRID_FRAMEBUFFER_WIDTH", "1600")
set_default_env("HYBRID_FRAMEBUFFER_HEIGHT", "900")
set_default_env("HYBRID_VOXELIZATION_BACKEND", "CPU")
set_default_env("HYBRID_CPU_VOXEL_RESOLUTION", "512")
set_default_env("HYBRID_CPU_SAMPLE_FREQUENCY", "512")
set_default_env("HYBRID_CPU_AUTO_GENERATE", "1")
set_default_env("HYBRID_CPU_LERP_NORMAL", "1")

base_script = Path(__file__).with_name("Voxelization_HybridMeshVoxel.py")
globals()["__file__"] = str(base_script)
exec(compile(base_script.read_text(encoding="utf-8"), str(base_script), "exec"), globals(), globals())
