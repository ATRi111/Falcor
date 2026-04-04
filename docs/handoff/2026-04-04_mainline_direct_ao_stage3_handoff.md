# Mainline DirectAO Stage3 Handoff

## 模块职责

`RayMarchingDirectAOPass` 现在已经进入阶段 3：新 pass 继续沿 stage 2 的 first-hit traversal 工作，但 `DirectOnly` / `Combined` 不再走随机 `sampleLight()`，而是改成遍历 analytic lights 的确定性直接光；`AOOnly` 仍然是 stage 4 之前的占位输出。

## 本阶段关键修复

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  `evalDeterministicDirectLighting()` 里，阴影可见性测试现在按每盏灯的 `lightDir` 选 `shadowNormal = bsdf.surface.getMainNormal(lightDir)`，再传给 `calcLightVisibility()`。
- 这次修复针对的症状是：黑色/阴影区域只和相机位置有关，和相机朝向基本无关。根因不是 traversal 主射线，而是 direct lighting 阶段阴影射线的起点偏移方向选错了。
- 同一个函数里新增了 `supportedLightCount` 统计，只把真正处理过的 `Point` / `Directional` 光算进来；如果场景没有受支持的 analytic light，仍会走 fallback ambient，避免场景因为未支持 light type 而整片过黑。

## 实现入口

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`

## 继续调试时优先看

- 如果仍有“黑区跟着相机走”的现象，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 里 `evalDeterministicDirectLighting()` 是否还有任何地方把 `viewDir` 用进阴影法线选择。
- 如果阴影位置大体对了，但依旧有自阴影或接触面发黑，下一步优先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang` 的 `calcLightVisibility()`，重点是 `shadowBias` 和 `distance - ignoreDistance` 的距离语义。
- 如果改完 pass/shader 后 GUI 里找不到新行为，不要只重新编 `Voxelization`；先补编 `Mogwai`，再启动 `Mogwai.exe` 验证插件加载。

## 当前验证状态

- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization` 已通过。
- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai` 已通过，产物为 `E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe`。
- `Mogwai` 编译日志里出现一次 Falcor 既有 warning：`Cannot enable D3D12 Agility SDK: Calling SetSDKVersion failed.`，但插件加载完成，日志显示 `Loaded 39 plugin(s)`。
- GUI 内的最终验收仍需手动完成：加载 scene，`ReadVoxelPass` 读取 cache，切到 `DirectOnly`，平移相机确认黑区不再跟位置错误联动。
