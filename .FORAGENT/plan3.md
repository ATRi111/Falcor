# Agent执行手册：主线 DirectAO 剩余阶段计划（plan3）

> 本文件取代 `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan2.md`，只覆盖 Stage4 及之后。
> Stage1-3 已完成，当前唯一主线基线是 `RayMarchingDirectAO*` + `scripts\Voxelization_MainlineDirectAO.py`。

## 1. 当前基线

当前仓库已经稳定完成以下内容：

- `RayMarchingDirectAOPass` 已注册并接入 `scripts\Voxelization_MainlineDirectAO.py`
- `RayMarchingTraversal.slang` 已从原 `RayMarching.ps.slang` 抽出主线可复用 traversal/visibility helper
- `RayMarchingDirectAO.ps.slang` 的 `DirectOnly` / `Combined` 已改为确定性 analytic direct lighting
- Stage3 的 primary-ray conservative fallback、`shadowNormal` 修正、unsupported light fallback 已验证通过

当前还没有完成的内容：

- `AOOnly` 仍是占位输出
- 主线 AO 还没有稳定、可验收的一帧结果
- `ReadVoxelPass` 还没有为 AO 提供新的辅助资源
- 更早的 `VoxelDirectAO*` 代码和文档仍残留在仓库里，后续应清理

## 2. 为什么从 plan2 升级到 plan3

`plan2.md` 的 Stage4-6 有两个主要问题：

1. 它把“runtime 固定方向 AO 验证”和“ReadVoxelPass 内完整方向性 AO 预计算”挤得太近，中间缺了一个更通用、更低风险的 `aoOccupancy` 层级结构。
2. 它把 `voxelOcclusion` 预计算写成了必做项，但结合当前仓库实现、Falcor 资源契约和 `deep_research.txt` 的 VXAO 思路，更合理的顺序是：
   - 先做稳定 AO baseline
   - 再补可采样的 occupancy mip
   - 再把 AO 从短射线升级到层级采样
   - 最后才决定是否真的需要方向性预计算和 stable env

本计划同时吸收以下现实约束：

- `docs/memory` 里已经确认 Stage1-3 的关键问题都集中在主线 `RayMarchingDirectAO*`，不应再回退到 `VoxelDirectAO*`
- `deep_research.txt` 提到的 VXAO / mip hierarchy 更适合作为 Stage5-6 的演进方向，而不是 Stage4 一步到位硬上完整预计算
- `shader-dev` 里的邻域 AO / 固定方向 AO 思路适合做 Stage4 的稳定 fallback，但不能直接替代当前工程的主线资源契约

## 3. 绝对约束

- 继续以 `RayMarchingDirectAO*` 为唯一实现主线；不要再把 `VoxelDirectAO*` 当成实现基线。
- 在 legacy 清理阶段真正执行前，`VoxelDirectAO*` 只能作为对照参考，不能继续往里加新逻辑。
- Stage4-6 不改 `.bin` 文件格式，不改 `VoxelizationPass.cpp` / `VoxelizationPass_GPU.cpp` 的写盘顺序。
- `ReadVoxelPass` 的既有输出契约必须保持兼容：`vBuffer / gBuffer / pBuffer / blockMap` 不能被替换，只能额外增加输出。
- AO 核心路径禁止重新引入 `frameIndex` 驱动的随机半球采样；允许的打散只能来自稳定空间 hash。
- primary hit 的 conservative fallback 是 Stage3 为 pinhole 修复保留的特例；AO/shadow 短射线默认不要直接复用同样的保守回退，否则很容易整体过黑。
- 只有在主线 AO 路线通过验证后，才允许进入 legacy `VoxelDirectAO*` 清理阶段。

## 4. 每阶段共用的验证流程

每个阶段结束至少做下面这些事：

1. 编译：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization
```

2. 如果改动涉及 pass 注册、脚本、shader 复制、ReadVoxelPass 资源反射或插件加载链路，再补：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai
```

3. 运行：

```powershell
E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py
```

4. GUI 内手测：
   - 加载与 cache 匹配的 scene
   - `ReadVoxelPass` 读入已有 `.bin`
   - 确认 `Solid Voxel Count > 0`
   - 切换 `DirectOnly / AOOnly / Combined / NormalDebug`

5. 画面确认以 Mogwai 窗口截图为准，不以离屏导出 png 为准。

## 5. Stage4：先做稳定 AO baseline，但仍只依赖现有 4 个输入

### 5.1 目标

在不改 `ReadVoxelPass` 输出契约的前提下，把主线 AO 从占位输出推进到“单帧稳定、可调、可观察”的 baseline。

这一阶段的 AO 不是最终性能形态，目标是先得到：

- `AOOnly` 可见且稳定
- `Combined` 有可信的 cavity / corner darkening
- AO 参数变更会正确 reset accumulation
- 画面不回退到 `VoxelDirectAO.ps.slang` 那种 `frameIndex` 驱动的随机噪点

### 5.2 本阶段要改的文件

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

### 5.3 实现策略

先做“两层 AO”，都只依赖现有 `vBuffer / gBuffer / pBuffer / blockMap`：

1. `contactAO`
   - 基于 `hit.cellInt` 周围局部邻域的占据关系做接触暗化
   - 重点补墙角、缝隙、体素交界处
   - 目标是低成本、极稳定、能作为后续 AO 的 debug 基线

2. `macroAO`
   - 使用固定 4/6 个半球方向做短距离 AO probe
   - 方向集围绕 `mainNormal` 构建
   - 只允许用 `hit.cellInt` 或 coarse tile 的稳定 hash 旋转，不能混入 `frameIndex`
   - 继续走现在的 `rayMarching()`，`ignoreFirst=true`

建议的最终组合：

```cpp
ao = lerp(1.0, contactAO * macroAO, aoStrength);
```

### 5.4 这一阶段不要做的事

- 不要重新使用 `UniformSampleGenerator(pixel, frameIndex)` 做 AO 主路径
- 不要直接把 AO 乘进 `bsdf.internalVisibility`
- 不要把 AO/shadow 短射线默认改成 conservative fallback
- 不要在这一阶段引入新的 ReadVoxelPass 输出

### 5.5 UI / 属性建议

至少新增：

- `aoEnabled`
- `aoStrength`
- `aoRadius`
- `aoStepCount`
- `aoDirectionSet`
- `aoContactStrength`
- `aoUseStableRotation`

如果 UI 太拥挤，允许先把 `aoDirectionSet` 和 `aoUseStableRotation` 写成属性而不全都暴露成 widget。

### 5.6 通过条件

- `AOOnly` 静止一帧就稳定，没有 Monte Carlo 雪花
- 缓慢移动相机时不出现明显 temporal shimmer
- `Combined` 能看到清晰但不过度发黑的接触暗化
- 改 AO 参数后 accumulation 会立即 reset

## 6. Stage5：在 ReadVoxelPass 里先补一个可采样的 occupancy mip，而不是马上做完整方向性 AO 预计算

### 6.1 目标

为后续 AO 升级提供一个通用、可复用的 3D occupancy hierarchy。

这是 plan3 相对 plan2 的关键改动：先做通用 `aoOccupancy`，再决定要不要上 `voxelOcclusion`。

### 6.2 本阶段要改的文件

新增：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\BuildAOOccupancy.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\GenerateAOOccupancyMip.cs.slang`

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

### 6.3 资源设计

新增一个可选输出：

- `aoOccupancy`

建议形式：

- `Texture3D`
- 带 mip chain
- 格式优先 `R8Unorm` 或 `R16Float`

不要首版就用 `R8Uint`：

- Stage6 如果要在 pixel shader 里按 LOD 采样 occupancy，整数纹理会让 filtered mip / sample-level 路径更别扭
- 这一层级结构的目标就是服务层级 AO，而不是只当 bitmask

### 6.4 数据来源

- base level 从 `vBuffer` 派生
- 必要时可结合 `gBuffer[offset].area > 0` 做更稳的 solid 判断
- 不要只依赖 `blockMap`；它只能当 coarse skip，不能当 AO 细节来源

### 6.5 通过条件

- 旧 `.bin` 仍然能被 `ReadVoxelPass` 正常读取
- 原 `Voxelization_GPU.py` 和主线 `Voxelization_MainlineDirectAO.py` 都不因新增输出而崩
- `aoOccupancy` 没接到 graph 时，Stage4 AO 结果不回退
- 资源尺寸、mip 数和当前 gridData 匹配

## 7. Stage6：把 AO 升级成“contact AO + occupancy mip 层级 AO”的主线版本

### 7.1 目标

把 Stage4 的短射线 `macroAO` 从“验证性 fallback”升级成真正的主线路径，同时保留 Stage4 作为 fallback/debug oracle。

### 7.2 本阶段要改的文件

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

### 7.3 实现策略

最终 AO 分成两部分：

1. `contactAO`
   - 继续沿用 Stage4 的局部接触 AO
   - 负责近场缝隙和锐利接触阴影

2. `hierarchicalAO`
   - 使用 `aoOccupancy` 做分层采样
   - 按方向步进时，采样 footprint 随距离增大，对应更高 mip
   - 可以是 cone tracing，也可以是 line tracing + `lod = log2(footprint)` 的近似版本

建议先做：

- 4 或 6 个固定方向
- 每个方向少量 step
- 累加 opacity/occlusion，超过阈值提前退出

组合建议：

```cpp
ao = lerp(1.0, contactAO * hierarchicalAO, aoStrength);
```

### 7.4 兼容策略

- `aoOccupancy` 不存在、未初始化或用户关闭时，自动回退到 Stage4 的 ray-based `macroAO`
- 这样 Stage4 不只是过渡方案，也是 Stage6 的回退路径和 debug 对照

### 7.5 通过条件

- `AOOnly` 比 Stage4 更平滑，且远处 cavity / corner darkening 更连贯
- `Combined` 不因 AO 升级而整体压暗
- 与 Stage4 相比，AO 运行开销下降或至少没有明显恶化
- `aoOccupancy` 开关关闭后能稳定回退到 Stage4 行为

## 8. Stage7：只有在确有必要时，才补方向性 occlusion/bent normal 预计算和 stable env

### 8.1 目标

这不是首轮验收的必做项，而是性能或外观驱动的二阶段优化。

只有满足下面任一条件时才做：

- Stage6 的 hierarchical AO 运行成本仍然过高
- 用户明确要求更稳定的环境项
- profile 表明 runtime AO 仍是主瓶颈

### 8.2 本阶段可能改的文件

新增：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AOStructures.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\BuildVoxelOcclusion.cs.slang`

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`

### 8.3 实现原则

- 方向性 occlusion / bent normal 必须建立在 Stage5 的 `aoOccupancy` 之上，不要重新从 `blockMap` 直接推导
- `voxelOcclusion` 是优化项，不是 Stage4-6 的前置条件
- stable env 如果要做，优先使用 bent normal 或 `dirOcc[6]` 的近似方向；不要回到 `sampleLight()` 或 `frameIndex` 随机 env 采样
- 即便做了预计算，也要保留 Stage6 的 runtime fallback

### 8.4 通过条件

- profile 能证明这一阶段确实降低了 AO 或 env 路径成本，或显著提升了稳定性
- 开关关闭时仍能回退到 Stage6
- 如果收益不明显，这一阶段允许跳过，不应阻塞后续清理和验收

## 9. Stage8：退役更早的 VoxelDirectAO* 路线（代码 + 文档）

### 9.1 目标

在主线 `RayMarchingDirectAO*` 路线通过 Stage4-6 验证后，把更早的 `VoxelDirectAO*` 彻底从代码和文档层面移除，避免之后的 Agent 再走错入口。

### 9.2 本阶段要处理的文件

代码删除：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_DirectAO.py`

代码修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`

文档清理：

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\voxel_direct_ao_plan.txt`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\ai_doc_navigation.txt`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\` 里提到 `VoxelDirectAO*` 仍可作为实施入口的旧文档
- `E:\GraduateDesign\Falcor_Cp\docs\memory\` 里如果有“继续用 `VoxelDirectAO*` 做实现基线”的旧表述，也一并修正

### 9.3 清理顺序

1. 先全仓搜索 `VoxelDirectAO`
2. 确认主线脚本只剩 `Voxelization_MainlineDirectAO.py`
3. 删除 legacy 代码文件
4. 删除 CMake / plugin 注册残留
5. 最后清文档和导航

### 9.4 通过条件

- `Voxelization` / `Mogwai` 编译通过
- 搜索不到仍在主动引用 legacy pass 的代码和脚本
- `.FORAGENT` 和 `docs/handoff` 的导航入口只指向主线 `RayMarchingDirectAO*`

## 10. 最终验收清单

全部阶段完成后，至少确认：

1. `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization` 通过
2. `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai` 通过
3. `scripts\Voxelization_GPU.py` 原 GI 路径仍可运行
4. `scripts\Voxelization_MainlineDirectAO.py` 可运行
5. `DirectOnly` 仍保持 Stage3 的确定性稳定
6. `AOOnly` 一帧稳定，无随机闪烁
7. `Combined` 既有 direct lighting，也有合理 AO
8. AO 参数变化会 reset accumulation
9. 如果做了 Stage7，关闭其开关后能回退到 Stage6
10. 如果做了 Stage8，全仓不再保留 active `VoxelDirectAO*` 实现入口

## 11. 后续 Agent 的优先阅读顺序

1. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
2. `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-04_mainline_direct_ao_stage3.md`
3. `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage3_handoff.md`
4. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
5. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
6. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
7. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
8. `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

