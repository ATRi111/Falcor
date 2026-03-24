# Mainline DirectAO Stage1 Handoff

## 模块职责

`RayMarchingDirectAOPass` 现在是主线 direct+AO 新路径的阶段 1 骨架：它已经能作为独立 render pass 被插件注册、被新 graph 引用，并通过 `RayMarchingDirectAO.ps.slang` 输出稳定纯色，为后续接 traversal / direct / AO 逻辑留出独立落点。

## 实现入口

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

## 继续开发时优先看

- 先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingPass.cpp` 和 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarching.ps.slang`，下一阶段的 traversal helper 会从这里抽公共函数，但不要把 GI 分支整体搬回新 pass。
- 如果新脚本打不开，优先检查 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.cpp` 的 pass 注册和 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt` 是否已经把 `RayMarchingDirectAO.ps.slang` 加进构建与 shader 复制链路。
- 如果命令行同时带 scene 和 script 启动时报 `DualHenyeyGreensteinPhaseFunction` type conformance 错误，先看 `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`：stage 1 纯色 shader 不能提前绑定 scene type conformances，否则 scene 加载后会在 FullScreenPass link 阶段失败。
- 如果需要验证阶段 1 是否还活着，先运行 `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`；当前正确行为是图能启动，`ReadVoxelPass` 接边正常，主输出应为稳定绿色纯色。
