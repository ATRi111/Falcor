# Mainline DirectAO Stage4 Handoff

## 模块职责

`RayMarchingDirectAOPass` 现在已经完成 plan3 的 Stage4：`AOOnly` 不再是占位输出，主线路径改为稳定的 `contactAO + macroAO` baseline，并继续只依赖 `ReadVoxelPass` 现有的 `vBuffer / gBuffer / pBuffer / blockMap` 四个输入。

## 本阶段关键实现

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  增加了稳定 AO helper：`contactAO` 用 4 个近场面环探测补局部接触暗化，`macroAO` 用 4/6 个固定半球方向短射线做中尺度遮蔽；方向集可选稳定旋转，但只允许使用 `hit.cellInt` hash，不使用 `frameIndex`。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  `Combined` 现在把确定性直接光乘上 Stage4 AO，`AOOnly` 改为显示 AO 调试视图，并额外做了更强的曲线映射，避免 ToneMapper 后看起来像全白占位图。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
  新增并下发了 `aoEnabled / aoStrength / aoRadius / aoStepCount / aoDirectionSet / aoContactStrength / aoUseStableRotation`，UI 改这些参数会继续设置 `RenderOptionsChanged`，同时把本地 `mFrameIndex` 归零。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
  主线脚本已支持同名环境变量，命令行可以直接切 `DIRECTAO_DRAW_MODE=2` 看 `AOOnly`，不需要手动点 UI。

## 继续工作时优先看

- 如果 `AOOnly` 又退回“几乎纯白”，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 里 `AOOnly` 分支是否仍保留 debug 曲线映射。
- 如果 `Combined` 开始出现明显 temporal shimmer，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 里 `evalStableAO()` 是否重新引入了 `frameIndex` 或逐帧随机旋转。
- 如果需要继续做 Stage5，不要改现有 `.bin` 读写格式；下一步应优先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp` 和 `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md` 里的 `aoOccupancy` 设计。

## 当前验证状态

- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization` 已通过。
- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai` 已通过，日志里仍有 Falcor 既有 warning：`Cannot enable D3D12 Agility SDK: Calling SetSDKVersion failed.`，但插件加载正常，显示 `Loaded 39 plugin(s)`。
- 已用窗口级截图验证 `Arcade + Voxelization_MainlineDirectAO.py` 的 `Combined` 正常打开并渲染。
- 已用 `DIRECTAO_DRAW_MODE=2` 的窗口级截图验证 `AOOnly` 不再是 stage3 的纯白占位输出，当前能看到稳定的 AO 轮廓分布。
