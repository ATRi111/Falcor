import os
import traceback


def env_int(name, default):
    value = os.environ.get(name)
    return int(value) if value not in (None, "") else default


def env_path(name, default):
    value = os.environ.get(name, "").strip()
    return value if value else default


capture_script = env_path("CAPTURE_SCRIPT", r"E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py")
capture_output_dir = env_path("CAPTURE_OUTPUT_DIR", r"E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2")
capture_basename = env_path("CAPTURE_BASENAME", "capture")
frame_count = env_int("CAPTURE_FRAME_COUNT", 4)
capture_path = os.path.join(capture_output_dir, capture_basename + ".png")

print("[Capture] script:", capture_script)
print("[Capture] output:", capture_output_dir)
print("[Capture] basename:", capture_basename)

try:
    m.ui = False
    print("[Capture] loading graph script")
    m.script(capture_script)
    m.clock.pause()

    for frame_index in range(1, frame_count + 1):
        print("[Capture] render frame", frame_index)
        m.clock.frame = frame_index
        m.renderFrame()

    print("[Capture] capture")
    m.captureOutput(capture_path)
except Exception:
    print("[Capture] failure")
    print(traceback.format_exc())
    raise
