# Plan4 Phase2 Mesh Direct Handoff

## 模块职责

本阶段只完成 plan4 Phase2 的 mesh deterministic direct 对齐：在不替换当前 voxel 主线的前提下，让 `HybridMeshDebugPass` 新增 `DirectOnly` 视图，用 `GBufferRaster` 的 mesh 几何/材质输入生成可单独查看的 mesh 直接光结果，作为后续 AO 对齐和中景 blend 的前置基线。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase2\arcade_near_mesh_normal_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase2\arcade_near_mesh_direct_only.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase2\arcade_near_voxel_direct_only_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase2_mesh_direct.md`

## 关键实现

- `HybridMeshDebugPass` 新增 `ViewMode::DirectOnly`，仍保持 Phase1 的 debug 视图职责不变；当前 Phase2 直接在这个 pass 内补 deterministic direct，避免提前改 voxel 主线或引入中景 blend 逻辑。
- 直接光实现完全走 mesh 侧：使用 `GBufferRaster` 提供的 `posW / normW / faceNormalW / viewW / diffuseOpacity / specRough / emissive`，再结合 scene analytic lights 和 inline ray query 做可见性判定。
- BRDF 口径尽量贴近当前 voxel 主线，核心仍是 Frostbite diffuse + Cook-Torrance GGX 风格的确定性 direct；如果场景 analytic light 不足，再退回稳定 sky/env fallback，避免 Phase2 直接视图完全黑掉。
- `Voxelization_HybridMeshVoxel.py` 默认 view mode 改为 `DirectOnly`，并补了 `HYBRID_MESH_SHADOW_BIAS` / `HYBRID_MESH_RENDER_BACKGROUND` 入口；脚本仍然只组织 `GBufferRaster -> HybridMeshDebugPass -> ToneMapper`，不会改动 `Voxelization_MainlineDirectAO.py`。
- 本轮额外修复了一个运行时 shader link 坑：`HybridMeshDebugPass.ps.slang` 中不能直接使用未定义的 `FLT_MAX`，否则不会在 C++ build 阶段报错，而会在 Mogwai 首帧执行 `FullScreenPass` 时抛 shader link 异常。

## 验证结论

- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh` 已通过。
- 已用 Mogwai 窗口级截图验证 `Arcade + near` 机位下：
  - `HYBRID_MESH_VIEW_MODE=Normal` 可正常出图，说明 Phase1 mesh debug 链路仍然稳定。
  - `HYBRID_MESH_VIEW_MODE=DirectOnly` 可正常出图，不再出现整窗纯白或运行时错误窗口。
  - `DIRECTAO_DRAW_MODE=1` 的 voxel 主线 smoke 仍可正常打开并出图，说明当前 baseline 未被替换。
- 当前窗口级截图里 mesh direct 与 voxel direct 的整图平均亮度已接近，可作为下一阶段 AO 对齐前的 direct 基线参考。

## 继续工作时优先看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase2_mesh_direct.md`

## 下一步建议

- 进入 Phase3 时优先继续走 mesh 侧，对齐 AO 或拆出独立 `MeshStyleDirectAOPass`；不要把 AO/blend 逻辑直接回灌到当前 voxel 主线。
- 如果后续 `HybridMeshDebugPass` 继续承载 AO、blend mask 等内容，职责会开始膨胀；在真正进入中景混合前，最好把 deterministic direct 从 debug pass 里拆出去，保留 `HybridMeshDebugPass` 只负责调试视图汇总。
- 继续做窗口级验收时，仍然要同时保留一张 voxel 主线 smoke 图；这样可以快速确认 mesh 侧改动没有悄悄影响现有 baseline。
