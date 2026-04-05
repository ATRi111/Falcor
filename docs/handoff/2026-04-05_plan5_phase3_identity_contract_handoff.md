# Plan5 Phase1-3 Current Hybrid Handoff

## 模块职责

当前 hybrid 开发基线，覆盖 plan5 已完成的 Phase1-3：scene `per-instance route`、route-aware mask/composite，以及 voxel identity / depth / normal / confidence contract。下一阶段是 Phase4 object-level composite，不是回头重开旧 plan。

## 当前状态

- Phase1 已完成：route 正式落在 `GeometryInstanceData.flags`，`Blend = 0` 作为默认值；scene runtime 与脚本 override 都能直接读写 instance route。
- Phase2 已完成：`HybridBlendMaskPass`、`HybridCompositePass`、`HybridMeshDebugPass` 统一通过 `vbuffer + gScene` 读取 route；`MeshOnly / VoxelOnly / Blend` 已不再只是纯距离带着色。
- Phase3 已完成：voxel 路径输出 `voxelDepth / voxelNormal / voxelConfidence / voxelInstanceID`；正式 identity 语义是 `dominant geometry instance ID`，`confidence = dominantInstanceArea / totalPolygonAreaInVoxel`，contributor tracking overflow 时必须保守失效。
- `RayMarchingDirectAOPass` 的 `outputResolution=0` 已改为跟随 graph 默认输出尺寸，避免 hybrid 在 `1600x900` 下出现 mesh / voxel 错位。
- 当前 `Arcade` 默认参考对象仍是 `Arch -> Blend`、`Cabinet -> MeshOnly`、`Chair -> Blend`、`poster -> VoxelOnly`；`RouteDebug` 颜色约定保持 `MeshOnly=orange`、`VoxelOnly=blue`、`Blend=green`。
- `scripts\Voxelization_HybridMeshVoxel.py` 是当前 hybrid 入口；`scripts\Voxelization_MainlineDirectAO.py` 仍要保留 smoke。
- Phase4 和 Phase5 都还未完成：非 blend 物体在当前 graph 下仍可能支付另一条正式路径的成本，`Composite / MeshOnly / VoxelOnly / BlendMask` 只是 correctness 调试口，不是最终 selective execution 验收结果。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneTypes.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneBuilder.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridBlendMaskPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridMeshDebugPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`

## 验证与证据

- 构建已串行复核：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization`
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh`
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`
- 图像证据保留在：
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase1\`
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase2\`
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\`
- 当前应优先复核的 hybrid 调试口：
  `RouteDebug`
  `BlendMask`
  `Composite`
  `VoxelDepth`
  `VoxelNormal`
  `VoxelConfidence`
  `VoxelRouteID`
  `VoxelInstanceID`
- mainline smoke 证据仍在 `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase3\arcade_near_mainline_directao_window.png`。

## 继续工作时优先看

- 先读 `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`，再读这份 handoff。
- 如果 route 语义异常，优先查 scene route contract 和 `HybridBlendMaskPass` / `HybridCompositePass` 的 `vbuffer + gScene` 接线。
- 如果 voxel debug 图失效，优先查 `ReadVoxelPass.cpp`、`RayMarchingDirectAOPass.cpp` 和 `RayMarchingDirectAO.ps.slang` 的 Phase3 contract。
- 如果删了 cache 后用 `HYBRID_CPU_AUTO_GENERATE=1` 重新验收，必须先生成 bin，再第二次启动 Mogwai 看新 cache；第一轮运行只负责写文件。

## 当前残余风险

- Phase4 object-level composite 还没有把 route、mesh depth、voxel depth 和 confidence 做成完整闭环。
- Phase5 selective execution 还没有把 `MeshOnly` / `VoxelOnly` 从另一条正式路径里真正剔除。
- host-side 会参与编译的 `.slang` / `.h` 仍应保持 ASCII 注释，避免 Windows `cl` / Slang 路径误读 UTF-8 中文后报假错误。
