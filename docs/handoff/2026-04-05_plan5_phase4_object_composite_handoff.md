# Plan5 Phase4 Object Composite Handoff

## 模块职责

当前 hybrid correctness 基线，完成 plan5 Phase4：composite 按对象 route 做单路/双路选择，`Blend` 只在 object/depth/confidence 同时允许时才引入 voxel。

## 当前状态

- `HybridCompositePass` 现在显式读取 `meshPosW` 计算 mesh depth，并在 `Composite` 视图里执行：
  `MeshOnly -> meshColor`
  `VoxelOnly -> voxelColor`
  `Blend -> distance base * voxel confidence * depth agreement * object match`
- `HybridBlendMaskPass` 仍只负责 route + 距离基权重；最终有效权重在 `HybridCompositePass.ps.slang` 二次收口，所以 `BlendMask` 视图现在显示的是 effective mesh/voxel weight，不再只是原始距离带。
- 新增 `ObjectMismatch` 和 `DepthMismatch` 两个输出模式，脚本入口已支持 `HYBRID_OUTPUT_MODE=objectmismatch|depthmismatch`。
- 本阶段只修 correctness，不做 Phase5 selective execution；`MeshOnly / VoxelOnly / Blend` 仍然会同时保留 mesh 和 voxel 正式链的成本。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`

## 验证与证据

- 构建通过：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh`
- `Arcade` near 窗口级 smoke 已完成：
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase4\arcade_near_hybrid_composite_window.png`
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase4\arcade_near_hybrid_objectmismatch_window.png`
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase4\arcade_near_hybrid_depthmismatch_window.png`
- 本轮未改 scene / voxel / contract 路径，因此没有额外 smoke `scripts\Voxelization_MainlineDirectAO.py`。

## 后续继续时优先看

- 如果 final composite 又回到“全局距离带 lerp”，先看 `HybridCompositePass.ps.slang` 里的 `effectiveVoxelWeight` 计算是否还保留 `route + depth + confidence + object match`。
- 如果 `ObjectMismatch` 或 `DepthMismatch` 退回整屏纯绿、纯黑或和 `VoxelConfidence` 一样的画面，先看 `MeshGBuffer.posW -> HybridCompositePass.meshPosW` 接线和脚本里的 `COMPOSITE_VIEW_MODES`。
- 如果用户下一步明确要求推进 Phase5，再去做 selective execution；不要继续在 Phase4 上做“更平滑的全局 blend”式调参。
