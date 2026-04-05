# Plan5 Phase3 Identity Contract Handoff

## 模块职责

本阶段把 voxel 路径补到 plan5 Phase3 所需的最小可用 contract：缓存和读取链路保留 dominant instance identity 与 confidence，ray marching 输出 depth / normal / confidence / instanceID，多张 Hybrid debug 视图和脚本接线全部打通，并保留 mainline 体素主线的可运行性。

## 本轮关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationShared.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AnalyzePolygon.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ClipMesh.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\SampleMesh.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_CPU.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationPass_GPU.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

## 当前语义与实现结论

- `voxel identity` 的正式语义是 `dominant geometry instance ID`，不是 route ID；Hybrid 的 `VoxelRouteID` 视图仍然是在 composite 里用 `instanceID -> gScene.getGeometryInstanceRenderRoute()` 现算。
- `confidence` 的正式语义是 `dominantInstanceArea / totalPolygonAreaInVoxel`；只要 contributor tracking overflow，就要保守地让 identity / confidence 失效。
- `ReadVoxelPass.cpp` 现在会识别 legacy cache layout，并把 legacy 读取出来的 `dominantInstanceID / identityConfidence` 归零，避免旧 cache 被误当成有效 Phase3 数据。
- `RayMarchingDirectAOPass` 现在会输出 `voxelDepth / voxelNormal / voxelConfidence / voxelInstanceID`，并在 graph 没有连接这些资源时为它们创建 fallback RT，避免脚本或 graph 少接线时直接崩掉。
- 本轮新增的 bugfix 在 `RayMarchingDirectAOPass.cpp`：`outputResolution=0` 不再硬编码 `1920x1080`，而是跟随 graph 的 `defaultTexDims` 和实际 color target size；否则 hybrid 在 `1600x900` 窗口下会把 voxel 图按错误分辨率读回，产生 mesh / voxel 明显错位。
- host-side `cl` / Slang 编译路径仍然会被共享 `.slang` / `.h` 里的中文注释坑到，表现为 UTF-8 被误读后吞掉后续代码并报出看似无关的编译错误；后续继续改这些 host 参与编译的文件时，注释请保持 ASCII。
- 已新增 `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat` 作为当前 hybrid 基线的一键启动入口；这个脚本使用 `REM + setlocal EnableDelayedExpansion`，避免 `cmd` 在解析带括号的 Arcade cache 路径时闪退。

## 验收流程与证据

- 启动 smoke：先确认没有残留 `Mogwai.exe`，再用 `scripts\Voxelization_HybridMeshVoxel.py` 起窗并检查 log，没有 `fatal / exception / failed`。
- 缓存重生成：删除 `E:\GraduateDesign\Falcor_Cp\resource\Arcade_(256, 171, 256)_256.bin_CPU` 后重新运行 hybrid，确认该 cache 重新生成。
- 重要流程注意点：删缓存后第一轮 `HYBRID_CPU_AUTO_GENERATE=1` 只负责把新 bin 写出来，因为 `ReadVoxelPass` 的 `binFile` 在脚本启动前就确定了；正式验收截图必须在 cache 生成完成后再次启动 Mogwai。
- 串行 build 已复核通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization`
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh`
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`
- Phase3 window 截图证据：
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_hybrid_composite_window.png`
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_hybrid_voxeldepth_window.png`
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_hybrid_voxelnormal_window.png`
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_hybrid_voxelconfidence_window.png`
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_hybrid_voxelrouteid_window.png`
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_hybrid_voxelinstanceid_window.png`
- Mainline smoke 证据：
  - `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_mainline_directao_window.png`
- 对截图的肉眼结论：
  - `composite` 中 mesh / voxel 已不再出现此前的分辨率错位，`Cabinet` 保持 `MeshOnly` 行为，近景不应把它误判成需要 blend 的对象。
  - `voxelDepth` 与 `voxelNormal` 都有稳定可视化，`voxelConfidence` 不是黑屏或随机噪声，只是 Arcade near 大部分像素都处于较高 confidence，所以图上接近高值配色。
  - `voxelRouteID` 与 `voxelInstanceID` 都能稳定区分对象，不是全黑，也不是随机闪烁噪声。

## 当前残余风险

- 本阶段只补完了 Phase3 contract 和 debug 视图，没有推进 Phase4 object-level composite 闭环，也没有做 Phase5 selective execution；`Blend` 对象当前仍然可能出现预期内的 mesh / voxel 混合痕迹。
- `HYBRID_CPU_AUTO_GENERATE=1` 的首轮运行仍是“先生成、后下次启动再验证”的工作流，如果后续想把单轮体验打通，需要额外改脚本或 `ReadVoxelPass` 的重新装载时机，但这不属于本次最小修复范围。

## 后续 Agent 优先查看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_phase3_identity_contract.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\`
