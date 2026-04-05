# Plan5 Phase5 MeshOnly Debug Fix And Arcade Cleanup Handoff

## 模块职责

修复 Phase5 selective execution 引入的 hybrid 调试回归，并把 Arcade hybrid 入口重新对齐到正确场景脚本与默认混合路由：保持 `Composite` 的对象级正式执行过滤不变，同时恢复 `MeshOnly`/`VoxelOnly` 等调试视图读取全场景源图的能力，避免 Arcade 再被旧 scene / 旧 route override 误导。

## 当前状态

- `HybridCompositePass` 现在会根据当前 `viewMode` 向 render graph dictionary 写入：
  `HybridMeshVoxel.requireFullMeshSource`
  `HybridMeshVoxel.requireFullVoxelSource`
- `GBufferRaster` 会在 `MeshOnly / BlendMask / RouteDebug / ObjectMismatch / DepthMismatch` 这些 hybrid 调试视图下临时把 `instanceRouteMask` 放宽为 `AllRoutes`，因此 `Arcade` 里的 `poster -> VoxelOnly` 不会再因为 Phase5 的 mesh selective execution 而在 `MeshOnly` 视图下显示为纯黑。
- `RayMarchingDirectAOPass` 也会在需要完整 voxel 源图的调试视图下临时放宽 route mask，避免 `VoxelOnly / VoxelDepth / VoxelNormal / VoxelConfidence / VoxelRouteID / VoxelInstanceID / ObjectMismatch / DepthMismatch` 继续读到被 selective execution 裁掉的 voxel 正式结果。
- `Composite` 视图本身不写这些 debug full-source 标记，所以 Phase5 的正式 selective execution 语义仍保持：
  `GBufferRaster = Blend|MeshOnly`
  `RayMarchingDirectAOPass = Blend|VoxelOnly`
- `run_HybridMeshVoxel.bat` 的默认 Arcade 入口已统一改到 `E:\GraduateDesign\Falcor_Cp\Scene\Arcade\Arcade.pyscene`，仓库里那个更暗的重复脚本 `media\Arcade\Arcade.pyscene` 已删除，避免 hybrid 与 PathTracer 对比时再落到不同 scene 配置。
- `scripts\Voxelization_HybridMeshVoxel.py` 已清空 `ARCADE_REFERENCE_ROUTES`，此前 `Cabinet -> MeshOnly` / `poster -> VoxelOnly` 的强制参考路由不再生效；当前 Arcade 默认实例都会回到 scene-builder 的 `Blend`。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_phase5_meshonly_debug_fix.md`

## 验证与证据

- 构建通过：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target GBuffer HybridVoxelMesh Voxelization Mogwai`
- `Arcade` near 窗口级 smoke 已完成：
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase5_meshonly_fix\arcade_near_meshonly_window.png`
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase5_meshonly_fix\arcade_near_composite_window.png`
  `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase5_meshonly_fix\arcade_near_routedebug_all_blend_window.png`
- 这轮 Arcade 入口清理没有继续改 shader 逻辑，用户已基于窗口结果确认 “删除暗场景 + 取消街机强制 Mesh/Voxel，全部回到混合” 没问题。
- 本轮没有改 voxel cache layout 或 mainline graph，因此没有额外重跑 `scripts\Voxelization_MainlineDirectAO.py`；代码改动边界仍是 hybrid 调试视图对 route mask 的读取方式，脚本层只改了 Arcade 默认 scene / route 覆写。

## 后续继续时优先看

- 如果 `MeshOnly`/`VoxelOnly` 再次出现“被另一条正式 selective execution 裁掉后整块发黑”的现象，先查 `HybridCompositePass.cpp` 的 dictionary flag 是否仍与 `viewMode` 对齐，再查 `GBufferRaster.cpp` / `RayMarchingDirectAOPass.cpp` 是否还在消费这些 flag。
- 如果后续新增新的 hybrid 调试视图，也要同步判断它是应该读取“正式 selective execution 源图”还是“调试用 full source”，不要默认沿用 `Composite` 的 route mask。
- 如果再出现 “hybrid 比 PathTracer 明显更暗” 但 shader 看起来没回归，先确认启动入口是不是 `Scene\Arcade\Arcade.pyscene`，再确认脚本里有没有重新塞回 Arcade 的强制 route overrides。
