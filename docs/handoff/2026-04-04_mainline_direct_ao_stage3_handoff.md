# Mainline DirectAO Stage3 Handoff

## 模块职责

`RayMarchingDirectAOPass` 现在已经进入阶段 3：新 pass 继续沿 stage 2 的 first-hit traversal 工作，但 `DirectOnly` / `Combined` 不再走随机 `sampleLight()`，而是改成遍历 analytic lights 的确定性直接光；`AOOnly` 仍然是 stage 4 之前的占位输出。

## 本阶段关键修复

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  `evalDeterministicDirectLighting()` 里，阴影可见性测试现在按每盏灯的 `lightDir` 选 `shadowNormal = bsdf.surface.getMainNormal(lightDir)`，再传给 `calcLightVisibility()`。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  针对 stage3 之后出现的“移动后随机位置白点”，已经确认这些点不是 direct lighting 火花，而是主射线被 ellipsoid refinement 漏成 miss 后把背景漏出来。现在主射线会先走 `rayMarching()`，若 miss 再回退到保守的 `rayMarchingConservative()`，把 solid voxel 当成命中补洞；这个回退只用于 primary hit，不改阴影射线语义。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  白点修复之后，曾尝试过“稳定 env lighting / stable shading normal”的附加改动，但它会把 `Arcade` 的能量分布和对比度拉偏，和原始验收图不一致；当前版本已回退这些附加改动，只保留 primary-ray conservative fallback，让白点修复与原有 stage3 光照行为解耦。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
  `isSolidVoxel()` 的越界判断已从 `offset > solidVoxelCount` 修成 `offset >= solidVoxelCount`，避免 helper 在极端 cache 上读出 `gBuffer[solidVoxelCount]`。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
  运行时会同步下发 `USE_ENV_MAP` define，确保 `RayMarchingDirectAO.ps.slang` 按当前 scene 是否存在 env map 走正确分支。
- 这次修复针对的症状是：黑色/阴影区域只和相机位置有关，和相机朝向基本无关。根因不是 traversal 主射线，而是 direct lighting 阶段阴影射线的起点偏移方向选错了。
- 同一个函数里新增了 `supportedLightCount` 统计，只把真正处理过的 `Point` / `Directional` 光算进来；如果场景没有受支持的 analytic light，仍会走 fallback ambient，避免场景因为未支持 light type 而整片过黑。

## 实现入口

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`

## 继续调试时优先看

- 如果仍有“黑区跟着相机走”的现象，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 里 `evalDeterministicDirectLighting()` 是否还有任何地方把 `viewDir` 用进阴影法线选择。
- 如果再次出现“表面白点/黑点”，先切 `NormalDebug` 并关闭 `renderBackground`：
  如果白点变黑点，优先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 里 primary hit 的 conservative fallback 是否还在，以及 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang` 里的 ellipsoid check 是否又引入了 pinhole。
- 如果阴影位置大体对了，但依旧有自阴影或接触面发黑，下一步优先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang` 的 `calcLightVisibility()`，重点是 `shadowBias` 和 `distance - ignoreDistance` 的距离语义。
- 如果改完 pass/shader 后 GUI 里找不到新行为，不要只重新编 `Voxelization`；先补编 `Mogwai`，再启动 `Mogwai.exe` 验证插件加载。
- 如果要确认 Mogwai 是否真的黑屏，不要看离屏导出脚本的 png；优先做“窗口级”截图，而且截图里不能混入 Codex 或其他前台窗口内容。

## 当前验证状态

- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization` 已通过。
- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai` 已通过，产物为 `E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe`。
- `Mogwai` 编译日志里出现一次 Falcor 既有 warning：`Cannot enable D3D12 Agility SDK: Calling SetSDKVersion failed.`，但插件加载完成，日志显示 `Loaded 39 plugin(s)`。
- 已用窗口专用截图验证 `run_DirectAO.bat` 打开的 `Arcade` 场景，当前整体明暗关系已经回到最初验收图附近，不再出现上一版那种墙面被整体抹亮、对比被压平的问题。
- 已用窗口专用截图验证 `NormalDebug + renderBackground=false`，当前表面 pinhole 已被补上，不再出现散布在墙面/地面的黑洞；对应的 `DirectOnly` 视图里原本的白点也一并消失。
- GUI 内仍可继续手动验收：切到 `DirectOnly`、平移相机，确认白点不再随移动换位置；如果后续还要改 env/ambient，务必和最初验收截图逐帧对比，不要把“去火花”的试验性光照改动混进白点修复。
