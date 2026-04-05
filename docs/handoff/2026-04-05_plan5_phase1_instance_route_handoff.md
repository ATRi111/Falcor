# Plan5 Phase1 Instance Route Handoff

## 模块职责

本阶段把 plan5 的 `per-instance` route 契约真正落到 scene runtime：scene instance 数据里现在能携带 `MeshOnly / VoxelOnly / Blend`，脚本可直接覆写 live scene route，`HybridCompositePass` 也新增了可视化 `RouteDebug` 输出用于在 Mogwai 中检查每个参考实例当前走哪条路径。

## 本轮产物

- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneTypes.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.h`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneBuilder.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase1\arcade_near_route_debug.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase1\arcade_mid_route_debug.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase1\arcade_far_route_debug.png`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase1\arcade_near_mainline_smoke.png`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_phase1_instance_route.md`

## 关键实现

- `SceneTypes.slang` 新增 `GeometryInstanceRenderRoute`，并把 route bit 编进 `GeometryInstanceData.flags`；为兼容旧实例默认值与未覆写路径，`Blend` 固定为零值。
- `Scene.slang` 新增 `getGeometryInstanceRenderRoute()`，shader 侧可以直接从 scene instance 数据读取 route。
- `Scene.cpp/.h` 把 route 从“脚本层约定”下沉为 runtime scene API，新增：
  - `scene.path`
  - `scene.geometry_instance_count`
  - `scene.get_geometry_instance_info(instance_id)`
  - `scene.get_geometry_instance_infos()`
  - `scene.set_geometry_instance_route(instance_id, route)`
  同时补了实例 node / geometry / material 名称查询，方便脚本稳定锁定参考对象。
- `SceneBuilder.cpp` 让当前 mesh/curve/SDF 实例默认 route 都落成 `Blend`，避免 builder 新路径出现未初始化 route。
- `scripts\Voxelization_HybridMeshVoxel.py` 现在会在场景载入后，把固定参考实例的 route 写回 live scene instance 数据，并支持：
  - `HYBRID_OUTPUT_MODE=RouteDebug`
  - `HYBRID_ROUTE_OVERRIDES=Name:Route,...`
  - `MeshGBuffer.vbuffer -> HybridCompositePass.vbuffer`
- 当前 `Arcade` 固定参考实例 route 为：
  - `Arch -> Blend`
  - `Cabinet -> MeshOnly`
  - `Chair -> Blend`
  - `poster -> VoxelOnly`
- `HybridCompositePass` 新增 `RouteDebug` 视图，直接按当前命中的 scene instance route 上色：
  - `MeshOnly` = orange
  - `VoxelOnly` = blue
  - `Blend` = green

## 验证结论

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh Mogwai`
- 已在 Mogwai 下对 `Scene\Arcade\Arcade.pyscene` 做 route debug 实窗验证，输出见 `docs\images\plan5_phase1\`：
  - `HYBRID_OUTPUT_MODE=RouteDebug` + `HYBRID_REFERENCE_VIEW=near`
  - `HYBRID_OUTPUT_MODE=RouteDebug` + `HYBRID_REFERENCE_VIEW=mid`
  - `HYBRID_OUTPUT_MODE=RouteDebug` + `HYBRID_REFERENCE_VIEW=far`
- 可视化结果与预期一致：
  - `Arch` / 房间主体为 `Blend` 绿色
  - `Cabinet` 为 `MeshOnly` 橙色
  - `poster` 为 `VoxelOnly` 蓝色
- 已额外用 `scripts\Voxelization_MainlineDirectAO.py` 对 `Arcade` 做 near 视角 smoke，`arcade_near_mainline_smoke.png` 说明 scene 核心改动没有把当前 mainline voxel 流程打坏。

## 后续 Agent 应优先查看

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\SceneTypes.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\Falcor\Scene\Scene.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\docs\images\plan5_phase1\`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_plan5_phase1_instance_route.md`

## 下一步注意点

- 这次只完成了 route contract、runtime 落盘和 debug 观测口；真正按 route selective 执行 mesh/voxel pass 仍属于 Phase2 之后的工作，不要在当前脚本 debug 分支里偷偷实现第二套正式逻辑。
- 继续扩参考实例时，优先复用 `scene.get_geometry_instance_infos()` 的名称检索结果做稳定映射，不要把 route 只记在 Python 局部字典里，否则一旦场景重载或后续 Pass 想读 route，契约又会退回脚本层。
