# Plan4 Phase1 Mesh Debug Handoff

## 模块职责

本模块只负责搭起 plan4 Phase1 的 mesh-only 可见性与调试链路：用 `GBufferRaster` 拉起 mesh 的 `depth / normal / base shading / material debug` 输出，并通过独立的 `HybridMeshDebugPass` 在 Mogwai 中单独查看 mesh 路径，不涉及 Phase2 之后的 direct/AO 对齐，也不替换当前 voxel 主线。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\CMakeLists.txt`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase1\arcade_near_mesh_base_shading_wait12.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase1\arcade_near_mesh_normal_wait12.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase1\arcade_near_mesh_depth_wait12.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase1\arcade_near_voxel_mainline_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase1_mesh_debug.md`

## 关键实现

- `HybridVoxelMesh` 是新增的独立插件目录，当前只有一个 `HybridMeshDebugPass`，职责限定为消费 `GBufferRaster` 的现有输出并生成 mesh-only debug color，不把 mesh 逻辑堆进 `Voxelization` 主线。
- `HybridMeshDebugPass` 当前支持 `BaseShading / Albedo / Normal / Depth / Emissive / Specular / Roughness` 几种视图；`BaseShading` 只是稳定的调试底色，不是 Phase2 要对齐的最终 direct lighting。
- `Voxelization_HybridMeshVoxel.py` 复用了 Phase0 的相机落位方式和 `HYBRID_REFERENCE_VIEW=near/mid/far` 入口，默认链路是 `GBufferRaster -> HybridMeshDebugPass -> ToneMapper`，不会接入当前 `ReadVoxelPass / RayMarchingDirectAOPass` 主线。
- Phase1 首选 `GBufferRaster` 已经足够拉起当前 mesh depth/normal/base shading 调试链路，暂时不需要把 `VBufferRT` 升级为主路径。

## 验证结论

- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh` 已通过。
- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai` 已通过，插件列表里已出现 `HybridVoxelMesh.dll`。
- 已用窗口级截图确认 `Voxelization_HybridMeshVoxel.py` 在 `Arcade` 近景机位下能稳定输出：
  - `BaseShading`
  - `Normal`
  - `Depth`
- 已额外用 `Voxelization_MainlineDirectAO.py` 做窗口级 smoke test，确认当前 voxel 主线仍能打开并出图，未被新 mesh 调试链路替换。

## 继续工作时优先看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase1_mesh_debug.md`
- `E:\GraduateDesign\Falcor_Cp\docs\development\2026-04-05_plan4_phase0_voxel_baseline.md`

## 下一步建议

- 如果进入 Phase2，优先在 `HybridVoxelMesh` 目录内新增 mesh direct/AO pass，不要把 Phase2 逻辑回灌到当前 `HybridMeshDebugPass` 或 `RayMarchingDirectAOPass`。
- Phase2 开始前先继续沿用 Phase0 冻结的 near/mid/far 机位做对齐，不要更换参考视角。
- 做窗口级截图验收时，不要在 Mogwai 窗口刚出现就立刻抓图；`Arcade` 在加载阶段会出现整窗纯白，需等待场景真正加载完再额外留约 10~12 秒。
