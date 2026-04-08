# Hybrid Composite Foreground Epsilon Handoff

## 模块职责

收紧 hybrid `Composite` 的前景深度判定，解决“voxel 不再整片消失，但高机位下只剩半只兔子”的残留问题。

## 本轮改动

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
  - 新增独立的 `evalCompositeDepthEpsilon()`。
  - `evalCompositeColor()` 不再复用 `evalDepthTolerance()` 这套 debug mismatch 容差，而是用更小的前景 epsilon 来决定 voxel 是否应抢到前面。

## 根因结论

- 上一轮已经修掉“voxel 完全被 mesh 地板盖没”的问题，但还残留一类更细的遮挡：
  - voxel 兔子和 mesh 地板在屏幕上深度很接近
  - `Composite` 用来做 debug 的宽容差允许 mesh 继续保留前景
  - 结果是贴地的兔子下半身更容易被当地板，尤其在相机抬高、俯视角更强时最明显
- 这不是 voxel ray marching 本身 miss，也不是 LOD route resolve 错，而是 composite 前景 epsilon 过大。

## 验证

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target HybridVoxelMesh Mogwai`
- 定向复现：
  - 强制高机位：`HYBRID_CAMERA_POSITION=0.0,3.3,4.9`
  - 保持 `Composite`
  - 验证截图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\composite_all_voxel_highcam_capture.png`
- 当前截图里，高机位下 voxel 兔子已不再出现明显“只剩半只”的大块裁断。

## 后续优先看

- 如果后面还出现局部缺口，先继续看 `HybridCompositePass.ps.slang` 的前景 epsilon，不要先回退到 `VoxelRoutePrepare` 或 `RayMarchingDirectAO`。
- `evalDepthTolerance()` 现在应只服务 debug/mismatch 观察；不要再直接拿它决定最终 composite 前景。
