# 主线 DirectAO 后续可选优化计划（plan3）

## 1. 文档定位

- 当前可验收、可展示的主线基线停在 Stage4。
- 当前主线基线是 `RayMarchingDirectAO*` + `scripts\Voxelization_MainlineDirectAO.py`，其目标已经是“稳定可展示的 voxel direct + AO”。
- 本文件只保留 Stage4 之后仍可能继续做的内容，而且全部都是可选项 / optional；它们不是当前主线必做项。
- 如果用户没有明确要求继续优化 AO、层级结构或环境项，不要因为看到了本文件就继续推进后续 stage。

## 2. 当前基线

当前仓库应以这条链路为准：

- `scripts\Voxelization_MainlineDirectAO.py`
- `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`

当前已经具备的基线能力：

- `DirectOnly` 使用确定性的 analytic direct lighting。
- `Combined` 已经是可展示的 direct + AO 主线结果。
- `AOOnly` 已经不再是占位输出，当前 AO 以 Stage4 的稳定 baseline 为准。
- 实际验收应以 Mogwai 窗口里的画面为准，不以离屏导出图为准。

## 3. 共用约束

- 后续优化仍只围绕 `RayMarchingDirectAO*` 主线；不要把 mesh 方案、legacy 方案或其他历史实验重新塞回这个计划。
- 不改 `.bin` 文件格式，不改 `VoxelizationPass.cpp` / `VoxelizationPass_GPU.cpp` 的写盘顺序。
- `ReadVoxelPass` 现有 `vBuffer / gBuffer / pBuffer / blockMap` 契约只能扩展，不能破坏。
- AO 核心路径禁止重新引入 `frameIndex` 驱动的随机半球采样。
- 任何 optional stage 都必须先保持 Stage4 基线外观不倒退，再谈继续推进。

## 4. Optional Stage5：`aoOccupancy` 层级结构

### 目标

把 `ReadVoxelPass` 扩展成能生成可采样的 3D occupancy mip，为后续层级 AO 提供通用输入。

### 主要改动区域

- `Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `Source\RenderPasses\Voxelization\CMakeLists.txt`
- 新增 occupancy 生成 shader
- `scripts\Voxelization_MainlineDirectAO.py`

### 实施要点

- 新增输出建议命名为 `aoOccupancy`。
- 资源形式优先 `Texture3D + mip chain`，格式优先 `R8Unorm` 或 `R16Float`。
- base level 从 `vBuffer` 派生；`blockMap` 只能做 coarse skip，不能替代细节占据源。
- 首版不要求立刻改变 AO 外观，先把资源契约和生成链路做稳。

### 主要风险

- `ReadVoxelPass.reflect()` 输出变化后脚本或 graph 接线失配。
- 资源尺寸、mip 数与 `gridData` 不一致会直接导致采样异常。

### 通过条件

- 旧 `.bin` 仍可正常读取。
- 主线脚本不因新增输出崩溃。
- `aoOccupancy` 不接入 shading 时，Stage4 基线结果不变。

## 5. Optional Stage6：层级 AO 主线路径

### 目标

把 Stage4 的 `contactAO + macroAO` 从“稳定 baseline”升级为“contact AO + occupancy mip 层级 AO”的主线路径，同时保留 Stage4 作为 fallback。

### 主要改动区域

- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `scripts\Voxelization_MainlineDirectAO.py`

### 实施要点

- `contactAO` 继续负责近场缝隙和接触暗化。
- `hierarchicalAO` 使用 `aoOccupancy` 做分层采样，按距离提高采样 footprint 或 mip level。
- 保留 Stage4 的 ray-based `macroAO` 作为 fallback/debug 对照，不要直接删掉。
- 目标是减少远距离 AO 的离散感和运行成本，而不是重新改变整体风格。

### 主要风险

- AO 变平滑后容易整体偏灰、偏闷。
- 只追求层级 AO 成本而忽略 Stage4 的接触暗化，会让近景丢层次。

### 通过条件

- `AOOnly` 比 Stage4 更平滑，但不过度发灰。
- `Combined` 不会突然整体变暗。
- 关闭新路径后能稳定回退到 Stage4 行为。

## 6. Optional Stage7：方向性 occlusion / bent normal / stable env

### 目标

只有在 Stage6 成本仍高、或用户明确要求更稳定的环境项时，才补方向性 occlusion、bent normal 或 stable env。

### 主要改动区域

- `Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `Source\RenderPasses\Voxelization\CMakeLists.txt`

### 实施要点

- 如果要做方向性 occlusion，优先建立在 `aoOccupancy` 或其派生结构上，不要重新从 `blockMap` 硬推。
- 如果要做 stable env，优先使用 bent normal 或方向性遮蔽近似，不要回到 `frameIndex` 随机采样。
- 这是优化项，不应改变 Stage4/Stage6 已经稳定下来的整体风格口径。

### 主要风险

- 环境项一旦能量口径不一致，很容易把现有基线整体抬亮或压暗。
- 方向性预计算收益不明显时，会徒增复杂度和维护成本。

### 通过条件

- profile 或实际画面能证明收益足够明显。
- 关闭该功能后仍能回退到 Stage6。

## 7. Optional Stage8：调参与性能收敛

### 目标

在不改变 Stage4 主体观感的前提下，对 AO 半径、强度、方向数、步数和 shader 成本做收敛式优化。

### 主要改动区域

- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `scripts\Voxelization_MainlineDirectAO.py`

### 实施要点

- 所有调参都必须以 Stage4 视觉口径为锚点。
- 优先减少“更亮、更灰、更硬”的风格漂移，而不是单纯追求更重 AO。
- 只有在 Mogwai 实际窗口画面确认不穿帮时，才接受参数收敛结果。

### 主要风险

- 为了压成本而削弱 AO，最后把当前可展示基线又改回去。
- 只看离屏图调参，会误判实际 Mogwai 画面。

### 通过条件

- 近景和中景的 Stage4 观感仍然成立。
- 开销下降或 UI/参数复杂度明显收敛。

## 8. 验证要求

任何 optional stage 完成后，至少检查：

1. `DirectOnly / AOOnly / Combined` 是否仍保持当前 Stage4 口径。
2. 静止观察时是否重新出现 temporal shimmer 或随机雪花。
3. 缓慢移动相机时是否突然变亮、变黑或出现 pinhole。
4. 验收截图必须来自 Mogwai 窗口实际画面，而不是离屏导图。

## 9. 后续 Agent 优先查看

1. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
2. `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_handoff.md`
3. `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_cleanup_handoff.md`
4. `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
5. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
6. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
7. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
8. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
