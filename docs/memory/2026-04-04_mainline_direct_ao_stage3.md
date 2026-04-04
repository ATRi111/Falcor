# 2026-04-04 Mainline DirectAO Stage3

- `RayMarchingDirectAO.ps.slang` 的确定性直接光里，给 `calcLightVisibility()` 的偏移法线必须按当前 `lightDir` 选，不能按 `viewDir` 选；如果用观察方向选 `getMainNormal()`，阴影射线会从错误一侧起步，现象就是黑区跟着相机位置走、与朝向弱相关。
- stage 3 不能只编 `Voxelization`；新增/修改 pass、shader 复制、插件加载链路以后，还要补跑 `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai`，否则只能证明 `Voxelization.dll` 能出，不能证明 `Mogwai.exe` 侧的插件发现和启动链路没坏。
- `evalDeterministicDirectLighting()` 里“是否没有可用 analytic light”不能直接看 `gScene.getLightCount()`；场景里可能存在当前未支持的 light type，这时应统计真正进入 point/directional 分支的数量，否则 fallback ambient 会被误跳过，画面容易整片发黑。
- stage 3 的命令行验证至少要分两层：
  1. 编译 `Voxelization`
  2. 编译 `Mogwai`
  真正的阴影/黑区是否修掉，仍需要在 GUI 中加载 scene、让 `ReadVoxelPass` 读 cache 后手动平移相机观察。
- 画面验收不能把离屏导出脚本产物当成最终依据。确认 Mogwai 是否黑屏时，要用系统级窗口截图直接抓 Mogwai 窗口，并确保截图里不夹带其他前台窗口内容；如果抓到整个桌面或其他窗口，结论无效。
- stage 3 后续出现“移动相机后表面冒白点”的第一判断，不要先怀疑 direct lighting 采样；先把 `RayMarchingDirectAOPass` 切到 `NormalDebug`，再把 `renderBackground` 关掉。如果白点立刻变成黑点，说明那不是着色火花，而是 primary ray 漏 hit 后把背景漏出来了。
- `CHECK_ELLIPSOID` 的 refinement 不是保守覆盖。`rayMarching()` 在某些 solid voxel 上会因为 `ellipsoid.clip()` miss 掉整条主射线，表现成稀疏 pinhole。对主射线最稳妥的修法不是直接全局关掉 ellipsoid，而是在 `RayMarchingDirectAO.ps.slang` 的 primary hit 路径上先走 ellipsoid 版本，miss 时再回退到“solid voxel 即命中”的保守 traversal。
- `RayMarchingTraversal.slang` 里原来的 `offset > solidVoxelCount` 是一个真实越界边界 bug，应该改成 `offset >= solidVoxelCount`。这次白点的 Arcade CPU cache 没踩到它，但 helper 里最好顺手修掉，避免以后别的 cache 触发读越界。
- 白点修复完成后，不要把“稳定 env lighting / stable shading normal”这类试验性光照改动一起提交。它们虽然也能压掉部分亮点，但会明显改变 `Arcade` 的整体亮度、墙面层次和对比度，和最初验收图不一致。最终应只保留 primary-ray conservative fallback，把“修 pinhole”和“改光照外观”严格分开。
