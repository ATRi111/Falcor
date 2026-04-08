# Hybrid Composite Depth Pick Handoff

## 模块职责

修复 hybrid instant LOD 的 `Composite` 前景选择：当同一像素同时存在 mesh 命中和 voxel 命中时，不再无条件返回 mesh，而是按深度决定实际前景，避免 `MeshOnly` 地板把 `VoxelOnly` 兔子盖掉。

## 本轮改动

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
  - `evalCompositeColor()` 现在在 `meshHitValid && voxelHitValid` 时比较 `meshDepth` / `voxelDepth`。
  - 当 voxel 比 mesh 至少近一个 `evalDepthTolerance()` 时，优先返回 `voxelColor`；否则保持 mesh 优先，避免同深度抖动。

## 根因结论

- 用户这轮现象不是 voxel path 本身失效，因为 `VoxelOnly` 视图一直正常。
- 真正问题在 `Composite`：
  - mesh GBuffer 对 `MeshOnly` 地板仍然有有效命中
  - voxel ray marching 对 `VoxelOnly` 兔子也有有效命中
  - 旧逻辑只要 mesh 有命中就直接返回 mesh，导致“后面的地板 mesh 覆盖前面的 voxel bunny”
- 所以从高机位看会误以为 voxel 兔子消失；把相机降到地板下面后，地板不再参与前景竞争，现象就“恢复正常”。

## 验证

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh Mogwai`
- 运行验证：
  - 用 `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat` 启动默认 `Composite` 机位后，窗口截图显示后排 voxel bunny 已正常出现在前景。
  - 验证截图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\composite_depthpick_capture.png`
  - 启动日志：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\composite_depthpick_bat_stdout.log`
  - `stderr` 只有 `libpng` profile warning：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\composite_depthpick_bat_stderr.log`

## 后续优先看

- 如果后面还看到 `Composite` 和 `VoxelOnly` 不一致，先看 `HybridCompositePass.ps.slang`，不要再先去怀疑 ray marching 或 route resolve。
- 如果要继续做更复杂的 hybrid blend，而不是 instant LOD，`meshDepth/voxelDepth` 的比较逻辑就是以后扩充 soft blend / confidence blend 的第一落点。
