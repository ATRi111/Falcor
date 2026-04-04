# Agent执行手册：主线 Voxel Direct Light + AO 落地计划

## 1. 任务定义

你不是来继续讨论方案，你是来按顺序把方案落地。

最终要交付的内容：

1. 新的主线风格 direct+AO pass
2. 新的 render graph 脚本
3. 稳定的确定性直接光
4. 稳定的固定方向 AO
5. 加载期生成的 AO 辅助体素结构
6. 不破坏原有 `RayMarchingPass` GI 路径

最终效果要求：

- 新路径基于当前主线链路独立实现，不把 direct+AO 分支继续堆进现有 `RayMarchingPass`
- 直接光默认不再依赖随机 `sampleLight()`
- AO 默认不再依赖逐帧随机半球采样
- 原有 `.bin` cache 读取顺序在 P0/P1 阶段保持不变
- 原 GI 路径仍可正常运行

## 2. 绝对约束

- 不要把仓库里现有的 `VoxelDirectAOPass` 当成主实现基线；最多只能借文件结构或 UI 写法，不能直接把本任务退化成“修现成 directAO 分支”
- P0/P1 不修改 `.bin` 文件格式，不修改 `VoxelizationPass.cpp` / `VoxelizationPass_GPU.cpp` 的写盘顺序
- 每完成一个小阶段，必须先编译和运行验证，再进入下一阶段
- 如果某个阶段没有验证通过，不要继续堆后续改动
- 只在新增路径上加功能，原 `RayMarchingPass` 只允许做“helper 抽取”这种低风险改动

## 3. 开工前先做这些事

### 3.1 必读文件

按顺序阅读：

1. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\ai_doc_navigation.txt`
2. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\voxelization_pipeline_brief.txt`
3. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\build_any_target_brief.txt`
4. `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_GPU.py`
5. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
6. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingPass.cpp`
7. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarching.ps.slang`
8. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\MixLightSampler.slang`
9. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`

### 3.2 开工前记录当前工作树

先执行：

```powershell
git -C E:\GraduateDesign\Falcor_Cp status --short
```

目的：

- 确认哪些文件本来就是脏的
- 后续不要误删已有 `VoxelDirectAOPass*` 相关未提交文件

### 3.3 先验证基线能编译

执行：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization
```

通过条件：

- `Voxelization` 目标编译成功

如果失败：

- 先不要写新代码
- 先确认失败是不是仓库当前已有脏改动导致

### 3.4 先验证主线图能跑

执行：

```powershell
E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_GPU.py
```

手动验证：

1. 加载和你当前 cache 对应的 scene
2. 在 `ReadVoxelPass` 里选择一个已有 `.bin` 文件并点击 `Read`
3. 确认：
   - `Solid Voxel Count` 大于 0
   - 原 `RayMarchingPass` 能正常出图

通过条件：

- 你有一个可复现的“现有主线路径可运行”基线

如果失败：

- 优先排查 scene 没加载、cache 选错、`ReadVoxelPass` 没 recompile

### 3.5 画面验证与截图规则

- 验证 Mogwai 实际出图时，优先使用系统级“窗口截图”工具抓取 Mogwai 窗口本身，不要把离屏导出脚本、frame capture 脚本或自动保存的 png 当成最终真值。
- 截图目标必须只包含 Mogwai 窗口内容，不能把 Codex、浏览器、任务管理器或其他前台窗口一起截进去。
- 如果当前前台不是 Mogwai，先把 Mogwai 切到前台，再使用活动窗口截图；如果工具支持窗口句柄，则优先按 Mogwai 的窗口句柄抓取。
- 除非任务明确要求抓整个桌面，否则不要使用全屏截图来判断渲染是否为黑屏。

## 4. 执行顺序总览

必须按下面顺序执行，不要跳步：

1. 阶段 1：新 pass 和新 graph 先跑通，哪怕先输出纯色
2. 阶段 2：抽 traversal helper，做 first-hit 调试图
3. 阶段 3：实现确定性 direct lighting
4. 阶段 4：实现固定方向 AO，但先只依赖现有 `vBuffer/gBuffer/pBuffer/blockMap`
5. 阶段 5：在 `ReadVoxelPass` 加 AO 辅助结构生成，并把新资源接到新 pass
6. 阶段 6：可选做稳定环境项
7. 最后：回归测试原 GI 图和新图

规则：

- 每一阶段结束都要重新编译 `Voxelization`
- 每一阶段都要跑 Mogwai 手测
- 每次只解决该阶段的问题，不顺手做 P1/P2 优化

## 5. 阶段 1：先把新 pass 和新 graph 骨架跑通

### 5.1 目标

先证明新路径可以独立存在。

这一步不追求正确光照，只追求：

- 新 pass 能被插件注册
- 新脚本能加载
- 新 graph 能接上 `ReadVoxelPass`
- 画面能输出一个稳定可见的调试颜色

### 5.2 本阶段要改的文件

新增：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\VoxelizationBase.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`

### 5.3 具体做法

#### Step 1：新增 pass 类

从 `RayMarchingPass.h/.cpp` 复制最小骨架，但删掉和 GI/NDF 相关的东西，只保留：

- scene / device / fullscreen pass 持有
- `reflect()`
- `execute()`
- `renderUI()`
- `setScene()`
- `mOptionsChanged`
- `mOutputResolution`
- `mFrameIndex`

不要保留：

- `mDisplayNDF`
- `mSelectedVoxel`
- `mMaxBounce`
- GI 专用 UI

#### Step 2：定义最小输入输出

`reflect()` 先完全对齐 `RayMarchingPass` 的输入：

- `vBuffer`
- `gBuffer`
- `pBuffer`
- `blockMap`

输出只保留：

- `color`

#### Step 3：shader 先输出纯色

`RayMarchingDirectAO.ps.slang` 第一版只做：

- full-screen pass
- 忽略 hit 结果
- 输出常量颜色，例如 `float4(0.2, 0.7, 0.2, 1)`

目的：

- 先验证 graph / pass / shader / plugin 注册没有问题

#### Step 4：注册 pass

在 `VoxelizationBase.cpp` 里注册新类。

#### Step 5：接入 CMake

在 `CMakeLists.txt` 中加入：

- 新 `.h`
- 新 `.cpp`
- 新 `.ps.slang`

#### Step 6：新增脚本

复制 `scripts\Voxelization_GPU.py` 为 `scripts\Voxelization_MainlineDirectAO.py`

只做这些改动：

- `RenderGraph` 名字改掉
- `RayMarchingPass` 替换为 `RayMarchingDirectAOPass`
- `AccumulatePass` 显式加 `autoReset=True`

### 5.4 本阶段验证

编译：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization
```

运行：

```powershell
E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py
```

手动步骤：

1. 加载与 cache 匹配的 scene
2. `ReadVoxelPass` 选择已有 `.bin`
3. 点击 `Read`

通过条件：

- Mogwai 能打开新脚本
- 新 pass 出现在图里
- 画面显示纯色，不是黑屏

失败排查：

- “找不到 pass”：查 `VoxelizationBase.cpp` 是否注册、插件是否重编译
- “shader 不生效”：查 `CMakeLists.txt` 是否添加并被 `target_copy_shaders()` 复制
- “纯黑”：先确认 `execute()` 里 FBO 已绑定 `color`

只有这一阶段通过后，才能继续。

## 6. 阶段 2：抽 traversal helper，并做 first-hit 调试图

### 6.1 目标

让新 pass 具备与原 `RayMarchingPass` 一致的主线 ray traversal 能力，但不带 GI。

最终你要得到：

- 新 pass 可以正确 hit/miss
- miss 输出背景
- hit 可以显示 normal / coverage 调试图

### 6.2 本阶段要改的文件

新增：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarching.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`

### 6.3 具体做法

#### Step 1：抽 helper

从 `RayMarching.ps.slang` 中抽出以下函数到新文件：

- `isSolidVoxel()`
- `isSolidBlock()`
- `checkPrimitive()`
- `rayMarching_DDA()` 两个重载
- `rayMarching_Mipmap()` 两个重载
- `rayMarching()`
- `calcLightVisibility()`

保留方式：

- 资源声明与 `cbuffer` 可以继续放在各自 shader 内
- helper 文件只放通用结构和函数

不要把这些也抽进去：

- `shadingGlobal()`
- `shadingDirect()`
- `coverageTest()`
- `debugShading()`

#### Step 2：新 pass 接入 first-hit

在 `RayMarchingDirectAO.ps.slang` 中加入：

- `screenCoordToCell()`
- camera ray 生成
- bbox `clip()`
- `rayMarching()`

第一版 draw mode 至少要有：

- `Combined`
- `DirectOnly`
- `AOOnly`
- `NormalDebug`
- `CoverageDebug`

这一阶段先只实现：

- `NormalDebug`
- `CoverageDebug`
- miss 背景

`Combined/DirectOnly/AOOnly` 可以先返回 placeholder。

#### Step 3：pass UI 对齐

在 `RayMarchingDirectAOPass.cpp` 里加入最小 UI：

- `drawMode`
- `renderBackground`
- `useMipmap`
- `checkEllipsoid`
- `checkVisibility`
- `checkCoverage`
- `shadowBias`
- `outputResolution`

### 6.4 本阶段验证

编译：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization
```

运行新脚本后手测：

1. `NormalDebug` 下，模型轮廓应与原 `RayMarchingPass` 的命中轮廓一致
2. miss 区域应该显示背景色，不是整屏纯色
3. 开关 `useMipmap / checkEllipsoid` 时，轮廓不应完全崩掉

通过条件：

- 画面不再是纯色
- 命中区域和原 GI 图的大轮廓一致
- `NormalDebug` 下法线看起来连续，不是全黑或全白

失败排查：

- 轮廓全错：优先查 `screenCoordToCell()`、`invVP`、`clip()`、`gridMin/voxelSize`
- 全部 miss：先看 `ReadVoxelPass` 的 `Solid Voxel Count`
- 一开 `checkEllipsoid` 就没图：查 `pBuffer` 和 `checkPrimitive()` 参数

## 7. 阶段 3：实现确定性 direct lighting

### 7.1 目标

把直接光从随机采样改成确定性遍历 analytic lights。

完成后预期：

- `DirectOnly` 在静止时一帧就稳定
- 相机移动后不会出现“重新收敛噪点”
- point / directional light 的阴影和亮面正常

### 7.2 本阶段要改的文件

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`

### 7.3 具体做法

#### Step 1：不要复用 `sampleLight()` 作为默认路径

新增一个函数：

- `evalDeterministicDirectLighting(HitResult hit, uint offset, float3 viewDir)`

实现要求：

1. 遍历 `gScene.getLightCount()`
2. 只处理：
   - `LightType::Point`
   - `LightType::Directional`
3. 对每盏灯计算：
   - `lightDir`
   - `distance`
   - `lightColor`
   - 点光源衰减
   - spotlight 参数如果现有 `LightData` 已包含，也一起处理
4. 使用现有 `calcLightVisibility()`
5. 使用现有 `PrimitiveBSDF.eval()` 流程求和

禁止事项：

- 默认 direct path 里不要再走 `sampleLight()`
- 不要把 env/emissive 混进这个函数

#### Step 2：关闭 GI 路径思维

新 pass 中不要实现：

- `shadingGlobal()`
- bounce 链
- `BSDF.sample()` 路径采样

只保留：

- first hit
- deterministic direct

#### Step 3：处理 draw mode

现在真正实现：

- `DirectOnly`
- `Combined` 先临时等于 `DirectOnly`

### 7.4 本阶段验证

编译后运行新脚本，测试：

1. `DirectOnly` 模式
2. 静止观察 5 秒
3. 缓慢移动相机
4. 改动 `shadowBias`

通过条件：

- 静止时没有 Monte Carlo 雪花噪点
- 移动相机时不会出现明显重新收敛
- 亮面/阴影位置基本合理

对照检查：

- 与原 `RayMarchingPass` 第一跳直接光相比，亮暗分区应该大体一致

失败排查：

- 过暗：优先查 `BSDF.updateCoverage()`、`calcInternalVisibility()` 是否叠得太狠
- 全亮无阴影：查 `calcLightVisibility()` 的起点偏移和 `distance / voxelSize.x`
- 点光源过爆：查距离平方衰减和 `distance <= 0`

## 8. 阶段 4：实现固定方向 AO，但先不引入新缓存资源

### 8.1 目标

先在不动 `ReadVoxelPass` 输出契约的前提下，把 AO 做成稳定版本。

完成后预期：

- `AOOnly` 一帧基本稳定
- `Combined` 有 cavity darkening
- 不出现逐帧闪烁噪点

### 8.2 本阶段要改的文件

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`

### 8.3 具体做法

#### Step 1：加入 AO 参数

最少加入：

- `aoEnabled`
- `aoSampleCount`
- `aoRadius`
- `aoStrength`
- `aoRotationMode`

推荐默认值：

- `aoEnabled = true`
- `aoSampleCount = 6` 或 `8`
- `aoRadius = 4` 到 `6`
- `aoStrength = 1`

#### Step 2：使用固定方向集

不要用 `UniformSampleGenerator` 每帧随机半球。

改成：

- 固定 4/6/8 个半球方向
- 推荐 Fibonacci hemisphere 或手写 cone directions

#### Step 3：旋转只允许空间打散，不允许时间打散

旋转来源只能是稳定 hash：

- `hit.cellInt`
- 或 8x8 tile
- 或屏幕像素，但不能包含 `frameIndex`

原因：

- 只想消 banding，不想重新引入 temporal shimmer

#### Step 4：AO 计算方式

对每个方向做短距离 `rayMarching()`：

- 起点：`hit.cell + shadowBias * mainNormal`
- 最大距离：`aoRadius`
- `ignoreFirst = true`

结果建议：

- 返回可见比例
- 最终组合使用：
  - `aoFactor = lerp(1, ao, aoStrength)`

不要直接把 AO 多次乘进 `BSDF.internalVisibility`

#### Step 5：先不要做 precompute

这一阶段 AO 仍然允许用现有 `rayMarching()`，只是采样方向变稳定。

### 8.4 本阶段验证

运行新脚本，测试：

1. `AOOnly`
2. `Combined`
3. 静止观察
4. 缓慢移动相机
5. 修改 `aoRadius` 和 `aoSampleCount`

通过条件：

- `AOOnly` 有清晰的 cavity / corner 暗化
- 静止画面不闪
- 相机移动时 AO 形状稳定，没有雪花噪点
- 改 `aoRadius` 后 accumulation 会 reset，不会拖影

失败排查：

- AO 全黑：查起点偏移是否仍在体素内部，查 `aoRadius`
- AO 几乎无效果：查方向集是否真的朝半球上方，查 `ignoreFirst`
- 有强条纹：增加方向数，或改为基于 `cellInt` 的稳定旋转
- 有闪烁：检查旋转 hash 是否错误使用了 `frameIndex`

## 9. 阶段 5：在 ReadVoxelPass 中生成 AO 辅助结构

### 9.1 目标

把 AO 从“每次 shading 都要做多条短射线”升级成“加载后生成辅助数据，运行时优先查结构”。

完成后预期：

- `AOOnly` 与阶段 4 外观接近或更平滑
- AO 运行成本下降
- 画面稳定性继续保持

### 9.2 本阶段要改的文件

新增：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\AOStructures.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\BuildAOOccupancy.cs.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\BuildVoxelOcclusion.cs.slang`

修改：

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.h`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\CMakeLists.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`

### 9.3 具体做法

#### Step 1：新增 AO 结构定义

在 `AOStructures.slang` 中定义：

```cpp
struct VoxelOcclusionData
{
    float aoMean;
    float dirOcc[6];
};
```

第一版先用 `float`，不要一开始就压缩到 `half`。

#### Step 2：ReadVoxelPass 增加“附加输出”，不是修改旧输出

`ReadVoxelPass` 保持原有输出不变，并额外添加：

- `aoOccupancy`
- `voxelOcclusion`

要求：

- 这是新增输出，不是替换原有输出
- 原 `vBuffer/gBuffer/pBuffer/blockMap` 契约保持兼容

#### Step 3：生成 `aoOccupancy`

建议形式：

- `Texture3D`
- 基础层从 `vBuffer` 派生
- 格式先用低精度整数或单通道格式，例如 `R8Uint`
- 再通过 compute 构建 mip

注意：

- 细节来源必须优先是 `vBuffer`
- 不要只依赖 `blockMap`，因为它分辨率太粗

#### Step 4：生成 `voxelOcclusion`

在 `BuildVoxelOcclusion.cs.slang` 中：

1. 遍历每个 solid voxel
2. 用 6 个主方向或 6 个 cone 方向估算局部遮挡
3. 写入：
   - `aoMean`
   - `dirOcc[6]`

这一步是加载期预计算，不是实时路径。

#### Step 5：新 pass 接收新增输入

修改 `RayMarchingDirectAOPass` 和脚本，新增边：

- `ReadVoxelPass.aoOccupancy -> RayMarchingDirectAOPass.aoOccupancy`
- `ReadVoxelPass.voxelOcclusion -> RayMarchingDirectAOPass.voxelOcclusion`

shader 中增加两套 AO 路径：

- fallback：阶段 4 的 fixed-ray AO
- preferred：查 `voxelOcclusion`，必要时结合 `aoOccupancy` 做 coarse 判断

策略：

- 默认优先走 precomputed AO
- 如果新资源不存在或未初始化，则自动回退到阶段 4

### 9.4 本阶段验证

编译并运行后，依次验证：

1. 新脚本图连接成功
2. `ReadVoxelPass` 读 cache 后没有崩
3. `AOOnly` 外观仍合理
4. 与阶段 4 比，静止图不应更差
5. 粗略观察 AO 计算是否更流畅

通过条件：

- `ReadVoxelPass` 新增资源生成不影响原资源上传
- `AOOnly` 和 `Combined` 可正常出图
- 关掉新 AO 开关时，能够回退到阶段 4 行为

失败排查：

- 读 cache 后黑屏：先查 `ReadVoxelPass.reflect()` 的资源尺寸是否依赖 header 正确更新
- compute 不执行：查 `mComplete`、`requestRecompile()`、dispatch 尺寸
- AO 结果全 1：查 `voxelOcclusion` 是否真的写入
- AO 结果全 0：查方向语义是否反了，或 `vBuffer` 空/实判定错

## 10. 阶段 6：可选增加稳定环境项

### 10.1 什么时候做

只有在阶段 5 已通过，且用户明确希望保留环境光时，才做这一阶段。

默认可以不做。

### 10.2 做法

新增：

- `evalStableEnvLighting()`

来源：

- 优先使用 AO 阶段顺手得到的 `bent normal`
- 如果你没有显式 bent normal，可先从 `dirOcc[6]` 近似恢复一个方向

禁止事项：

- 不要把 env 再塞回 `sampleLight()`
- 不要引入逐帧随机 env 采样

### 10.3 验证

测试：

1. 开环境项前后切换
2. 静止 5 秒
3. 缓慢移动相机

通过条件：

- 环境项打开后不出现明显 speckle
- 相机移动时不出现重新收敛闪点

## 11. accumulation reset 必须在每个阶段都检查

新 pass 中，以下变化必须触发：

- `drawMode`
- `useMipmap`
- `checkEllipsoid`
- `checkVisibility`
- `checkCoverage`
- `shadowBias`
- `aoEnabled`
- `aoRadius`
- `aoSampleCount`
- `aoStrength`
- direct mode
- env mode
- 文件切换
- 相机变化

执行要求：

- 所有 UI 改动都把 `mOptionsChanged = true`
- `execute()` 里通过 `RenderOptionsChanged` 通知图
- graph 中 `AccumulatePass` 必须 `autoReset=True`

验证方法：

1. 停留 20 帧让 accumulation 稳定
2. 改一个 AO 参数
3. 观察结果

通过条件：

- 画面立即刷新
- 没有拖尾和残影

## 12. 每阶段都要跑的编译与运行命令

编译插件：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization
```

如果 pass 注册或脚本报错，再补编：

```powershell
cd E:\GraduateDesign\Falcor_Cp
tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Mogwai
```

运行原图：

```powershell
E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_GPU.py
```

运行新图：

```powershell
E:\GraduateDesign\Falcor_Cp\build\windows-vs2022\bin\Release\Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py
```

## 13. 最终验收清单

全部完成后，必须逐项确认：

1. `Voxelization` 目标能编译
2. 原 `scripts/Voxelization_GPU.py` 仍能运行
3. 新 `scripts/Voxelization_MainlineDirectAO.py` 能运行
4. `ReadVoxelPass` 能读旧 `.bin`
5. `DirectOnly` 一帧稳定
6. `AOOnly` 一帧稳定，无闪烁噪点
7. `Combined` 画面合理
8. 参数变化能 reset accumulation
9. 原 GI 图没有被破坏

## 14. 如果某一步失败，先看哪里

### 症状：新脚本打不开

优先检查：

- `VoxelizationBase.cpp` 是否注册新 pass
- `CMakeLists.txt` 是否包含新文件
- shader 是否被复制到运行目录

### 症状：读 cache 后仍然黑屏

优先检查：

- scene 是否加载
- `ReadVoxelPass` 是否点击了 `Read`
- `Solid Voxel Count` 是否大于 0
- graph 边是否接对

### 症状：DirectOnly 仍然有随机噪点

优先检查：

- 是否还有路径在调用 `sampleLight()`
- 是否仍保留 `randomJitter()`
- 是否误把 env/emissive 作为默认 direct 核心路径

### 症状：AO 有闪烁

优先检查：

- AO 方向旋转是否用了 `frameIndex`
- 是否仍然使用 `UniformSampleGenerator` 做半球随机

### 症状：AO 有严重 banding

优先检查：

- 方向数是否过少
- 旋转 hash 是否只按屏幕空间固定，导致图案明显
- 能否改为按 `cellInt` 做稳定旋转

### 症状：原 GI 路径坏了

优先检查：

- helper 抽取是否改动了 `RayMarchingPass` 的行为
- `RayMarching.ps.slang` 是否被你顺手改了 GI shading 逻辑

## 15. 本任务明确不要做的事

- 不要把整个实现继续塞回现有 `RayMarchingPass`
- 不要一开始就上 SVGF、A-trous、reprojection
- 不要一开始就改 `.bin` 文件格式
- 不要默认把 env/emissive 作为低噪点核心路径
- 不要在未经验证的情况下连续堆多个阶段的改动

## 16. 完成后必须补的文档

完成代码后，必须同步更新：

- `E:\GraduateDesign\Falcor_Cp\docs\memory\`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\`

memory 至少记录：

- 哪一步最容易出错
- 哪个资源尺寸/重编译机制最容易漏
- 新 AO 结构是如何绑定的

handoff 至少写清：

- 新 pass 负责什么
- 哪几个文件是实现入口
- 调试 DirectOnly / AOOnly 时优先看哪里
