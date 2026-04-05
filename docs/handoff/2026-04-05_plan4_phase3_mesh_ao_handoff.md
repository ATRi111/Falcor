# Plan4 Phase3 Mesh AO Handoff

## 模块职责

本阶段完成 plan4 Phase3 的 mesh AO 对齐底座，并顺手把 Stage2 的 deterministic direct 从 `HybridMeshDebugPass` 拆到独立 `MeshStyleDirectAOPass`：`MeshStyleDirectAOPass` 只负责 mesh `DirectOnly / AOOnly / Combined`，`HybridMeshDebugPass` 重新收回到 `BaseShading / Albedo / Normal / Depth / Emissive / Specular / Roughness` 这些纯 debug 视图，不引入 voxel 主线改造，也不提前做中景 blend。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\CMakeLists.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase3\arcade_near_mesh_combined.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase3\arcade_near_mesh_direct_only.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase3\arcade_near_mesh_ao_only.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase3\arcade_near_mesh_normal_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase3\arcade_near_voxel_combined_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase3_mesh_ao.md`

## 关键实现

- `MeshStyleDirectAOPass` 新增了独立的 mesh style pass，输入仍然只吃 `GBufferRaster` 的 `posW / normW / faceNormalW / viewW / diffuseOpacity / specRough`，输出单张 `color`，当前支持：
  - `Combined`
  - `DirectOnly`
  - `AOOnly`
- deterministic direct 基本沿用了 Phase2 的 analytic light + inline ray query 口径，只是从 debug pass 挪到了新 pass 里，避免 `HybridMeshDebugPass` 继续膨胀。
- AO 走 mesh 侧的稳定 world-space 半球探测：
  - 保留 voxel baseline 的 `contactAO + macroAO` 分层思路；
  - 稳定旋转来自 `posW` 量化后的 cell hash，不引入 `frameIndex` 或时间随机；
  - `AOOnly` 继续用 `pow(ao, 12)` 做调试映射，避免接近 1 的 AO 在 `ToneMapper` 后看起来像“没生效”。
- `HybridMeshDebugPass` 已移除 `DirectOnly` 逻辑，重新只保留纯 mesh debug 输出；脚本层通过 `HYBRID_MESH_VIEW_MODE` 路由：
  - `Combined / DirectOnly / AOOnly` 走 `MeshStyleDirectAOPass`
  - `BaseShading / Albedo / Normal / Depth / Emissive / Specular / Roughness` 走 `HybridMeshDebugPass`
- `scripts\Voxelization_HybridMeshVoxel.py` 仍然只组织 mesh 侧图：
  - `GBufferRaster -> MeshStyleDirectAOPass -> ToneMapper`
  - 或 `GBufferRaster -> HybridMeshDebugPass -> ToneMapper`
  不会替换 `scripts\Voxelization_MainlineDirectAO.py`。

## 验证结论

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh`
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`
- 已在 Mogwai 实窗下做窗口级截图验证，参考机位均为 `Arcade + near`，并按 Phase1 memory 的做法等待约 35 秒后再抓图：
  - `HYBRID_MESH_VIEW_MODE=Combined` 可正常出图，见 `arcade_near_mesh_combined.png`
  - `HYBRID_MESH_VIEW_MODE=DirectOnly` 可正常出图，说明 deterministic direct 在拆分到新 pass 后仍可单独查看，见 `arcade_near_mesh_direct_only.png`
  - `HYBRID_MESH_VIEW_MODE=AOOnly` 可正常出图，能看到接触暗化和大尺度遮蔽，见 `arcade_near_mesh_ao_only.png`
  - `HYBRID_MESH_VIEW_MODE=Normal` 仍可正常出图，说明 debug pass 路由未被拆分破坏，见 `arcade_near_mesh_normal_smoke.png`
  - `scripts\Voxelization_MainlineDirectAO.py` 在 `DIRECTAO_DRAW_MODE=0` 下仍可正常打开并出图，见 `arcade_near_voxel_combined_smoke.png`

## 继续工作时优先看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase3\`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase3_mesh_ao.md`

## 下一步建议

- 如果继续留在 Phase3，优先拿 Phase0 冻结的 near/mid/far 机位，把 mesh `Combined` 和 voxel baseline 逐张对齐 AO 强度、接触半径和墙角暗化，不要先跳去做 blend mask。
- 如果下一步进入 Phase4，中景 blend 之前优先保留当前拆分：`MeshStyleDirectAOPass` 负责正式 mesh style，`HybridMeshDebugPass` 只负责 debug 视图；不要再把 blend 或 voxel 兼容逻辑回灌进 debug pass。
- 当前 AO 半径仍是 mesh world-space 经验值，后续如果要跨场景复用，最好补一个更稳定的 mesh AO 标尺策略，或者在真正做 hybrid 合成前把 direct/AO helper 再抽一层共享 include。
