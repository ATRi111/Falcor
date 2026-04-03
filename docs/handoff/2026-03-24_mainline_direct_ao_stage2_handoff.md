# Mainline DirectAO Stage2 Handoff

## 模块职责

`RayMarchingDirectAOPass` 现在已经从阶段 1 的纯色骨架进入阶段 2：它会沿主线 voxel traversal 做 first-hit，支持 `NormalDebug`、`CoverageDebug` 和 miss 背景，`Combined` / `DirectOnly` / `AOOnly` 仍故意保留为 placeholder，方便后续只在新路径上继续接 deterministic direct 和稳定 AO。

## 实现入口

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarching.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`

## 继续开发时优先看

- 如果 stage 3 要接确定性直接光，先从 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 的 first-hit 主流程继续往下加，不要把 `shadingGlobal()` 或 bounce 逻辑搬回新 pass。
- 如果 `NormalDebug` 轮廓不对或全 miss，优先检查 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 里的 `screenCoordToCell()`、`clip()` 入格点逻辑，以及 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang` 的 `rayMarching()` / `checkPrimitive()`。
- 如果运行时又出现 `CHECK_*` / `USE_MIP_MAP` 未定义警告，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang` 顶部的默认宏和 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp` 里 `FullScreenPass` 创建时的初始 define。
- 如果 GUI 里看起来还是整屏背景，先确认 `ReadVoxelPass` 已经读入 cache；阶段 2 的自动烟测只验证了脚本和 scene 启动，不会替你点 `Read`。

## 当前验证状态

- `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization` 已通过。
- `Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py` 启动 12 秒烟测通过，无启动崩溃。
- `Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py --scene E:\GraduateDesign\Falcor_Cp\Scene\Box\CornellBox.pyscene` 启动 12 秒烟测通过；日志里仅剩 Falcor 既有的 warning 和 `Math/VoxelizationUtility.slang` 的旧 warning。
- `NormalDebug` / `CoverageDebug` 的 GUI 目测、miss 背景确认、`useMipmap` / `checkEllipsoid` 切换后的轮廓检查仍需在桌面 GUI 中手动完成。
