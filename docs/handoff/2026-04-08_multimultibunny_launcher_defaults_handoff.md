# MultiMultiBunny Launcher Defaults Handoff

## 模块职责

- 三个 launcher 现在默认都以 `MultiMultiBunny` 作为启动场景：
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Mesh.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
- `run_VoxelBunny_Blend.bat` 额外显式固定了：
  - `HYBRID_PIPELINE_MODE=hybrid`
  - `HYBRID_OUTPUT_MODE=composite`
  让它默认走当前的瞬切 hybrid LOD 主路径，而不是脚本外部环境里遗留的其他 execution mode。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Mesh.bat`
  - 默认 scene 改成 `Scene\MultiMultiBunny.pyscene`
  - 默认 cache 前缀改成 `resource\MultiMultiBunny_(128, 9, 128)_128.bin_CPU`
- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
  - 默认 scene / cache / scene hint 全部切到 `MultiMultiBunny`
- `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
  - 默认 scene / cache / scene hint 全部切到 `MultiMultiBunny`
  - 默认 execution env 固定为 instant-switch hybrid/composite

## 验证

- 已做 launcher smoke：
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Mesh.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
  - `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
- 验证日志：
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multimultibunny_mesh_stdout.log`
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multimultibunny_voxel_stdout.log`
  - `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multimultibunny_blend_stdout.log`

## 后续优先看

- 如果后面还要继续调 `MultiMultiBunny` 的 route / cache / launcher，优先看：
  - `E:\GraduateDesign\Falcor_Cp\Scene\MultiMultiBunny.pyscene`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
  - `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-07_multimultibunny_scene.md`
