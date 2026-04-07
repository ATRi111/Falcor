import os
from pathlib import Path


def set_default_env(name, value):
    if not os.environ.get(name):
        os.environ[name] = value


repo_root = Path(__file__).resolve().parent.parent

set_default_env("HYBRID_REPO_ROOT", str(repo_root))
set_default_env("HYBRID_SCENE_PATH", str(repo_root / "Scene" / "MultiBunny.pyscene"))
set_default_env("HYBRID_SCENE_HINT", "MultiBunnyDense1p5Lerp")
set_default_env("HYBRID_FORCE_ALL_ROUTE", "MeshOnly")
set_default_env("HYBRID_OUTPUT_MODE", "meshview")
set_default_env("HYBRID_MESH_VIEW_MODE", "combined")
set_default_env("HYBRID_FRAMEBUFFER_WIDTH", "1600")
set_default_env("HYBRID_FRAMEBUFFER_HEIGHT", "900")

base_script = Path(__file__).with_name("Voxelization_HybridMeshVoxel.py")
globals()["__file__"] = str(base_script)
exec(compile(base_script.read_text(encoding="utf-8"), str(base_script), "exec"), globals(), globals())
