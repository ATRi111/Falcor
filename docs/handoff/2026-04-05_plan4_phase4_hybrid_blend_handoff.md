# Plan4 Phase4 Hybrid Blend Handoff

## 模块职责

本阶段完成 plan4 Phase4 第一版 hybrid 合成链路：保留 mesh 侧 `GBufferRaster + MeshStyleDirectAOPass`、保留 voxel 主线 `ReadVoxelPass + RayMarchingDirectAOPass`，新增独立的 `HybridBlendMaskPass` 和 `HybridCompositePass`，让 `scripts\Voxelization_HybridMeshVoxel.py` 能在同一张图里实现“近景 mesh、远景 voxel、中景平滑 blend”，而不把正式 hybrid 逻辑继续堆回 `HybridMeshDebugPass`。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\CMakeLists.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\arcade_near_hybrid_composite.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\arcade_mid_hybrid_composite.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\arcade_far_hybrid_composite.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\arcade_near_hybrid_blend_mask.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\arcade_mid_hybrid_blend_mask.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\arcade_near_voxel_mainline_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase4_hybrid_blend.md`

## 关键实现

- `HybridBlendMaskPass` 当前只吃 `MeshGBuffer.posW`，按相机到 mesh hit 的 world-space 距离生成 mesh 权重；默认参数是：
  - `blendStartDistance = 1.50`
  - `blendEndDistance = 3.25`
  - `blendExponent = 1.0`
- `HybridCompositePass` 只负责在线性空间按 `meshWeight` 混合 `meshColor` 和 `voxelColor`，同时保留 `Composite / MeshOnly / VoxelOnly / BlendMask` 四种查看模式，便于后续调 blend 区。
- `scripts\Voxelization_HybridMeshVoxel.py` 现在拆成两种运行模式：
  - `HYBRID_OUTPUT_MODE=MeshView`：保留 Phase1-3 的 mesh-only 调试入口，继续用 `HYBRID_MESH_VIEW_MODE`
  - `HYBRID_OUTPUT_MODE=Composite/MeshOnly/VoxelOnly/BlendMask`：走新的 Stage4 完整 hybrid graph
- Stage4 第一版没有改 `Voxelization_MainlineDirectAO.py`，也没有扩 `RayMarchingDirectAOPass` 的额外输出；当前 blend 只依赖 mesh 距离带和现有 voxel `color`，先保证链路成立。
- 为避免 mesh 默认 framebuffer 和 voxel `1920x1080` 输出尺寸不一致，hybrid 脚本在完整 graph 模式下会默认把 Mogwai framebuffer 对齐到 voxel 输出分辨率；若后续改 `HYBRID_VOXEL_OUTPUT_RESOLUTION`，记得同步看这条对齐逻辑。

## 验证结论

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh`
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`
- 已在 Mogwai 实窗下做窗口级截图验证，场景均为 `Scene\Arcade\Arcade.pyscene`，并按前序阶段经验等待约 45 秒后抓图：
  - `HYBRID_OUTPUT_MODE=Composite` + `HYBRID_REFERENCE_VIEW=near`：`arcade_near_hybrid_composite.png`
  - `HYBRID_OUTPUT_MODE=Composite` + `HYBRID_REFERENCE_VIEW=mid`：`arcade_mid_hybrid_composite.png`
  - `HYBRID_OUTPUT_MODE=Composite` + `HYBRID_REFERENCE_VIEW=far`：`arcade_far_hybrid_composite.png`
  - `HYBRID_OUTPUT_MODE=BlendMask` + `HYBRID_REFERENCE_VIEW=near`：`arcade_near_hybrid_blend_mask.png`
  - `HYBRID_OUTPUT_MODE=BlendMask` + `HYBRID_REFERENCE_VIEW=mid`：`arcade_mid_hybrid_blend_mask.png`
- 在把默认 blend 距离外推到 `1.50 -> 3.25` 后，又补做了一轮中景实窗复核：
  - `HYBRID_OUTPUT_MODE=Composite` + `HYBRID_REFERENCE_VIEW=mid`：`arcade_mid_hybrid_composite_v2.png`
  - `HYBRID_OUTPUT_MODE=BlendMask` + `HYBRID_REFERENCE_VIEW=mid`：`arcade_mid_hybrid_blend_mask_v2.png`
- 已额外用 `scripts\Voxelization_MainlineDirectAO.py` 做窗口级 smoke，`DIRECTAO_DRAW_MODE=0` + `DIRECTAO_REFERENCE_VIEW=near` 下 baseline 仍能正常出图，见 `arcade_near_voxel_mainline_smoke.png`。

## 继续工作时优先看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan4_phase4\`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan4_phase4_hybrid_blend.md`

## 下一步建议

- 当前 blend 只用 mesh 距离带，能拉起第一版链路，但还没有利用 voxel depth / normal / confidence 修正遮挡差；如果后续在边缘看到重影、空洞或过早切换，优先给 voxel pass 补最小必要的 hit/depth 信号，而不是先把 blend 区盲目放宽。
- `blendStartDistance / blendEndDistance` 目前是 Arcade 经验值，后续若跨场景复用，最好补一轮 near/mid/far 对齐，再决定是否引入更稳定的距离标尺或深度一致性修正。
- 当前 `MeshOnly / VoxelOnly / BlendMask` 都已经能通过 `HybridCompositePass` 查看；下一阶段如果要继续调 style 对齐，尽量沿用这三个调试口，不要再把正式 hybrid 逻辑塞回 `HybridMeshDebugPass`。
