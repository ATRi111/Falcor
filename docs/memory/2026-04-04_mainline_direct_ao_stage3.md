# 2026-04-04 Mainline DirectAO Stage3

- `RayMarchingDirectAO.ps.slang` 的确定性直接光里，给 `calcLightVisibility()` 的偏移法线必须按当前 `lightDir` 选，不能按 `viewDir` 选；如果用观察方向选 `getMainNormal()`，阴影射线会从错误一侧起步，现象就是黑区跟着相机位置走、与朝向弱相关。
- stage 3 不能只编 `Voxelization`；新增/修改 pass、shader 复制、插件加载链路以后，还要补跑 `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`，否则只能证明 `Voxelization.dll` 能出，不能证明 `Mogwai.exe` 侧的插件发现和启动链路没坏。
- `evalDeterministicDirectLighting()` 里“是否没有可用 analytic light”不能直接看 `gScene.getLightCount()`；场景里可能存在当前未支持的 light type，这时应统计真正进入 point/directional 分支的数量，否则 fallback ambient 会被误跳过，画面容易整片发黑。
- stage 3 的命令行验证至少要分两层：
  1. 编译 `Voxelization`
  2. 编译 `Mogwai`
  真正的阴影/黑区是否修掉，仍需要在 GUI 中加载 scene、让 `ReadVoxelPass` 读 cache 后手动平移相机观察。
