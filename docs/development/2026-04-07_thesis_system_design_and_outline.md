# 毕业论文技术说明与大纲草案

## 1. 文档定位

这份文档用于把当前仓库中已经完成的实现，整理成可以直接转写到本科毕业论文中的技术说明。重点不是把系统包装成“已经完全收敛的最终工业级 LoD 优化器”，而是把它准确表述为：

- 一个基于 Falcor 的实时渲染原型系统。
- 一个围绕“体素作为远景代理”展开的混合渲染研究与实现。
- 一个已经完成体素化、体素直接光照、体素 AO、Mesh 对照渲染、Mesh/Voxel 混合合成与对象级 route 验证的原型。
- 一个已经能够说明视觉可行性，但在性能层面仍暴露出“双路径并行执行”瓶颈的系统。

如果后续要写论文正文，建议优先复用本文件中的技术口径，而不是直接照搬开题报告中“远景自动切换后显著提速”的理想化描述。

## 2. 论文中的总体定位

### 2.1 推荐的课题表述方式

论文可以写成：

“本文围绕体素作为远景几何代理的思路，设计并实现了一套基于 Falcor 的实时渲染原型系统。系统包括离线体素化、基于体素的直接光照与环境光遮蔽、Mesh 对照渲染链路，以及面向 Mesh/Voxel 融合的混合渲染管线。通过实验，本文验证了体素代理在远景直接光照与 AO 表达中的可行性，并分析了对象级混合渲染在执行层面的性能瓶颈。”

这个表述有几个好处：

- 保留了开题报告里“体素作为 LoD 代理”的主线。
- 不需要硬说“最终性能优化已经完全达成”。
- 能把现在仓库里最扎实的部分，即原型实现、功能验证和瓶颈分析，全部纳入论文贡献。

### 2.2 不建议在正文里硬写的结论

下面这些说法不建议直接写：

- “本文已经实现了高效的最终 LoD 系统。”
- “本文已经实现了完全无缝切换且显著提速的远景体素 LoD。”
- “本文已经让远景对象完全脱离 Mesh 正式渲染链，并稳定获得明显性能提升。”

原因是当前代码虽然已经有对象级 route 和 selective execution 的结构，但默认 hybrid 场景仍可能保留双路径正式链开销，特别是：

- 默认对象 route 大多仍为 `Blend`。
- `MeshOnly`、`VoxelOnly`、`RouteDebug` 等很多模式本质是调试或开发视图，不等同于真正的全局性能模式。
- 体素路径的 selective execution 仍是 hit-level，而不是 route-aware block-level，残余遍历成本仍然存在。

### 2.3 推荐的论文贡献描述

论文中可以把贡献收敛为以下几项：

1. 在 Falcor 中实现了面向复杂场景的离线体素化与体素缓存生成流程。
2. 在体素表示上实现了稳定的直接光照与 AO 渲染基线。
3. 实现了用于对照的 Mesh 渲染链路，并建立了 Mesh 与 Voxel 的统一观察和调试方式。
4. 实现了支持 `MeshOnly`、`VoxelOnly`、`Blend` 三类对象语义的混合渲染原型。
5. 分析了对象级 route 在视觉正确性与执行成本之间的工程矛盾，并指出了当前性能瓶颈来源。

## 3. 整个框架的思想

### 3.1 整体思路

当前系统并不是单一路径的渲染器，而是由三条相关但职责不同的链路组成：

1. 体素主线。
   这条链路用于证明体素表示本身可以完成直接光照和 AO 渲染，是论文里最稳定、最容易验收的主展示链。

2. Mesh 对照链。
   这条链路不是为了替代体素，而是为了提供近景参考、高频几何细节参考，以及混合阶段的对照基线。

3. Hybrid 混合链。
   这条链路用于验证“同一场景中不同对象或不同距离区域，可以在 Mesh 与 Voxel 之间进行组合表达”的想法，并进一步探索 route-aware 的对象级混合与 selective execution。

因此，论文里不要把系统写成“体素已经完全取代远景 Mesh”。更准确的描述是：

- 体素主线负责远景代理与快速可视化。
- Mesh 主线负责保留高精度几何细节和近景质量。
- Hybrid 管线负责研究两者如何组合，以及这种组合在工程上会遇到什么问题。

### 3.2 架构设计原则

当前代码中的关键设计思想可以概括成四点：

1. 预处理与实时阶段分离。
   体素化采用离线缓存生成，而不是每帧都重新构建体素数据，目的是把大部分昂贵数据构建挪到预处理阶段。

2. 表示与显示分离。
   体素缓存中不仅保存“有没有体素”，还保存可用于着色的表面统计信息、椭球拟合信息以及对象身份信息，为后续直接光照、AO 和混合决策提供依据。

3. 调试视图与正式执行分离。
   当前代码中特意保留了 `RouteDebug`、`BlendMask`、`ObjectMismatch`、`DepthMismatch` 等视图，用来观察系统是否正确，而不是直接把“看起来像单路显示”误认为“已经减少了执行成本”。

4. route 统一落在 Scene 实例数据中。
   对象应该走 Mesh、Voxel 还是 Blend，不是由某个 pass 私下决定，而是写入 `GeometryInstanceData.flags` 的 route 位中，让 Mesh 路径、Voxel 路径和 Composite 路径都读同一份契约。

### 3.3 论文里可以怎样描述框架

可以写成：

“本文采用分层式实时渲染架构。底层以 Falcor RenderGraph 为组织方式，中层分为体素渲染、Mesh 渲染和混合渲染三条链路，上层通过统一的场景实例 route 信息协调不同对象的渲染表示。该架构在保证各条链路可独立调试的同时，为后续研究对象级 LoD 切换和选择性执行提供了基础。”

## 4. 体素化方案

### 4.1 体素化方案在系统中的位置

体素化模块的职责不是直接出图，而是把原始三角网格转换成后续体素渲染所需的缓存数据。其目标包括：

- 建立规则体素网格。
- 对落入同一体素的多边形贡献做统计与聚合。
- 生成体素索引和稀疏表示。
- 把结果写入二进制缓存，供运行时快速读取。

在代码上，这部分主要对应：

- `Source/RenderPasses/Voxelization/VoxelizationPass.cpp`
- `Source/RenderPasses/Voxelization/VoxelizationPass.h`
- `Source/RenderPasses/Voxelization/VoxelizationShared.slang`
- `Source/RenderPasses/Voxelization/PrepareShadingData.cs.slang`
- `Source/RenderPasses/Voxelization/ReadVoxelPass.cpp`

### 4.2 为什么采用离线体素化

论文里可以把离线体素化写成一个主动选择，而不是“没做实时体素化”的退而求其次：

- 场景几何复杂时，体素化生成本身成本较高。
- 毕设重点是验证体素作为 LoD 代理时的直接光照、AO 和混合渲染可行性，而不是做全动态场景重建。
- 离线缓存可以让运行时更专注于采样、遍历、着色和混合逻辑，便于观察系统行为。

因此，本文选择先把体素数据离线生成到缓存，再在运行时通过 `ReadVoxelPass` 读取。

### 4.3 体素网格与缓存组织方式

当前体素缓存由四类核心数据构成：

1. `GridData`
   记录整个体素网格的空间范围、体素尺寸、体素分辨率、block 数量和 solid voxel 数量等信息。

2. `vBuffer`
   一个 3D 纹理/索引结构，用于把体素单元映射到真实的稀疏体素数据偏移。可以理解为“从规则网格坐标查到稀疏有效体素”的入口。

3. `VoxelData`
   这是每个实心体素真正的核心数据结构，定义在 `VoxelizationShared.slang` 中。除材质外观与几何拟合信息外，还包含：
   - `dominantInstanceID`
   - `identityConfidence`

   这两个字段是后续对象级混合的关键，因为它们让 voxel 不再只是“颜色块”，而是带有对象身份语义的远景代理。

4. `blockMap`
   用于支持更粗粒度的空间跳跃和稀疏遍历，减少空体素区域上的无效检查。

缓存文件写出流程在 `VoxelizationPass::write()` 中完成，文件内容顺序为：

- `GridData`
- `vBuffer`
- `VoxelData`
- `blockMap`

### 4.4 体素属性如何聚合

从论文角度，体素化并不是简单把三角形涂进格子里，而是做了“表面响应聚合”。当前 `VoxelData` 中主要包括：

- `ABSDF`
  用于概括体素内部表面在远场观察下的材质与法线分布特征。
- `Ellipsoid`
  用于近似体素内几何分布，帮助命中判断和后续可见性估计。
- `primitiveProjAreaFunc`
- `polygonsProjAreaFunc`
- `totalProjAreaFunc`

这些投影面积函数配合 `PrimitiveBSDF` 使用，可以恢复：

- 可见覆盖率 `coverage`
- 内部可见性 `internal visibility`
- 主法线方向

这意味着当前方案并不是传统意义上的“仅颜色体素”，而是一个包含外观统计信息的体素代理结构。

### 4.5 对象身份与置信度设计

这是论文里值得单独强调的点。

当前 `VoxelData` 额外保存：

- `dominantInstanceID`
- `identityConfidence`

其含义可以写成：

- `dominantInstanceID` 表示该体素内占主导贡献的几何实例。
- `identityConfidence` 表示该体素能否可靠代表该对象，数值越高说明这个体素更接近“单对象主导”的情况。

这个设计的意义在于：

- 让体素结果可以和 Mesh 命中结果做对象级比对。
- 为 `HybridCompositePass` 提供“是否值得混合”的依据。
- 避免在对象边界或多个对象共享体素时盲目混合。

### 4.6 运行时读取流程

运行时不直接重建体素，而是：

1. `ReadVoxelPass` 读取缓存文件。
2. 输出 `vBuffer`、`gBuffer`、`pBuffer` 和 `blockMap`。
3. 通过 `PrepareShadingData.cs.slang` 把 `VoxelData` 拆分为运行时着色所需的 `PrimitiveBSDF` 和 `Ellipsoid`。

这种设计把“缓存格式”和“运行时着色格式”解耦开了，论文里可以写成：

“本文采用离线缓存与运行时结构分离的方式，既便于缓存持久化，也便于运行时按着色需要组织数据。”

### 4.7 体素化方案的优点与局限

优点：

- 支持离线重用，运行时加载成本可控。
- 能保存超出传统颜色体素的信息，如法线分布、覆盖率、对象身份和置信度。
- 为后续直接光照、AO 和对象级混合奠定了统一数据基础。

局限：

- 当前仍是全局体素缓存，而不是 per-object 独立体素代理。
- 当前 blockMap 还不是 route-aware 的，因此 selective execution 仍存在残余遍历成本。
- 离线体素化更适合静态或准静态场景，对全动态场景适配有限。

## 5. 体素渲染方案

### 5.1 主链路结构

体素主链路由脚本 `scripts/Voxelization_MainlineDirectAO.py` 组织，核心 RenderGraph 为：

`VoxelizationPass -> ReadVoxelPass -> RayMarchingDirectAOPass -> ToneMapper`

其中：

- `VoxelizationPass`
  在需要时生成体素缓存。
- `ReadVoxelPass`
  读取缓存并准备运行时数据。
- `RayMarchingDirectAOPass`
  负责屏幕空间发射视线、在体素网格中遍历并计算直接光照与 AO。
- `ToneMapper`
  做最终显示映射。

### 5.2 体素射线遍历方式

当前体素渲染的本质是屏幕空间逐像素 ray marching。`RayMarchingDirectAO.ps.slang` 会：

1. 从当前像素和逆视图投影矩阵恢复视线方向。
2. 把世界空间射线映射到体素网格坐标。
3. 调用 `rayMarching()`、必要时调用 `rayMarchingConservative()` 等遍历逻辑。
4. 借助 `vBuffer`、`gBuffer`、`pBuffer` 和 `blockMap` 判断命中。

从论文写法上，可以把它描述为：

“本文采用基于规则体素网格和稀疏索引结构的屏幕空间射线步进方法，在体素空间内完成首命中搜索，并在命中位置上进行直接光照与环境光遮蔽计算。”

### 5.3 体素直接光照实现

当前直接光照不是随机路径追踪，而是确定性地遍历场景 analytic light：

- 点光源和方向光优先作为稳定直接光源。
- 对每个光源计算方向、强度和距离。
- 通过体素空间的可见性判断进行遮挡检测。
- 结合 `PrimitiveBSDF` 的 BRDF 评估得到直接光照结果。

对应代码在：

- `RayMarchingDirectAO.ps.slang`
- `Shading.slang`

它的优点是：

- 结果稳定。
- 更适合毕设阶段做重复实验和截图比较。
- 可以避免逐帧随机采样带来的噪声和时间闪烁。

### 5.4 体素 AO 实现

体素 AO 当前采用“接触 AO + 宏观 AO”两部分组合：

1. `contactAO`
   用于增强接触区域和局部缝隙的遮蔽感。

2. `macroAO`
   用于在更大半径上估计周围几何对环境光的遮挡。

为了减少闪烁，AO 方向集不是逐帧随机旋转，而是：

- 基于命中体素单元的稳定 hash 生成固定旋转角。
- 在相同位置复现相同采样分布。

论文里可以把这部分写成：

“为了兼顾视觉层次与结果稳定性，本文将体素 AO 划分为接触尺度与宏观尺度两部分，并采用基于体素单元哈希的稳定方向旋转，降低逐帧抖动。”

### 5.5 体素渲染输出内容

当前体素路径不只输出颜色，还会输出以下调试与混合相关数据：

- `color`
- `voxelDepth`
- `voxelNormal`
- `voxelConfidence`
- `voxelInstanceID`

这几项输出的意义非常大，因为它们使体素路径不仅能单独成图，还能与 Mesh 路径在 Hybrid 阶段对齐。

### 5.6 体素渲染方案的优点与局限

优点：

- 对远景几何细节能形成稳定的体积代理。
- 直接光照和 AO 均已跑通，可形成完整展示结果。
- 输出了深度、法线、对象身份和置信度，为混合渲染提供了可靠中间量。

局限：

- 体素路径仍依赖预处理缓存，不适合高频动态场景。
- 精度受体素分辨率和聚合策略影响。
- 目前 selective execution 仍未解决 block-level 的 residual traversal cost。

## 6. Mesh 渲染方案

### 6.1 Mesh 路径在系统中的职责

Mesh 路径不是论文的附属部分，而是整个系统中不可缺少的对照与近景链路。它承担三项职责：

1. 提供高精度近景结果。
2. 为体素路径提供质量对照。
3. 为 Hybrid 管线提供 Mesh 侧输入。

### 6.2 Mesh 主链路结构

当前 Mesh 渲染主要由以下模块构成：

- `GBufferRaster`
- `MeshStyleDirectAOPass`
- `HybridMeshDebugPass`

脚本 `scripts/Voxelization_HybridMeshVoxel.py` 中的 Mesh-only 图通常组织为：

- `MeshGBuffer -> MeshStyleDirectAOPass -> ToneMapper`
或
- `MeshGBuffer -> HybridMeshDebugPass -> ToneMapper`

### 6.3 GBuffer 设计

当前 GBuffer 中保留的关键结果包括：

- `posW`
- `normW`
- `faceNormalW`
- `viewW`
- `diffuseOpacity`
- `specRough`
- `emissive`
- `vbuffer`

这些数据既用于 Mesh 路径自身的着色，也用于 Hybrid 混合时和体素路径做对齐，例如：

- `posW` 可用于计算 Mesh 深度。
- `vbuffer` 可用于查询命中实例 ID。
- `normW` 与 `faceNormalW` 可用于直接光照与 AO。

### 6.4 Mesh 直接光照与 AO

`MeshStyleDirectAOPass.ps.slang` 的逻辑和体素路径保持了尽量一致的审美方向：

- 对 analytic lights 做确定性直接光照估计。
- 通过可见性测试做阴影判断。
- 使用稳定方向集做 AO。

这条链路的意义在于：

- 不是简单做一个“传统 PBR 结果”，而是尽量和体素路径在观察维度上对齐。
- 这样后续做 Hybrid 时，两个输入源的差异不会完全来自渲染模型不一致。

### 6.5 Mesh 调试视图

`HybridMeshDebugPass.ps.slang` 提供了多种观察模式：

- `BaseShading`
- `Albedo`
- `Normal`
- `Depth`
- `Emissive`
- `Specular`
- `Roughness`
- `RouteDebug`

其中 `RouteDebug` 非常重要，因为它能直接显示每个对象当前属于：

- `Blend`
- `MeshOnly`
- `VoxelOnly`

这使得 route 语义不再停留在脚本配置上，而可以直接在画面中观察。

### 6.6 Mesh selective execution 的实现基础

当前 Mesh selective execution 的核心不在 shader 里，而在 `GBufferRaster -> Scene::rasterize()` 这条路径上。具体来说：

- `GBufferRaster` 新增了 `instanceRouteMask` 属性。
- `Scene::rasterize()` 可以根据 route mask 过滤 draw args。
- `Scene` 会缓存不同 route mask 下的 filtered draw buffers。

这部分在论文里可以写成：

“为了避免将对象级路由仅停留在屏幕空间混合层，本文进一步在 Mesh 正式渲染入口处引入了基于实例 route 的 draw filtering 机制，为后续选择性执行提供基础。”

### 6.7 Mesh 路径的作用总结

论文里可以用一句话概括：

“Mesh 路径既是近景高精度结果的主要来源，也是评估体素代理质量与构建混合渲染的参考基线。”

## 7. 混合渲染实现方式

### 7.1 混合渲染的目标

混合渲染的目标不是简单把两张图线性叠起来，而是研究：

- 哪些对象应该只走 Mesh。
- 哪些对象应该只走 Voxel。
- 哪些对象可以同时持有两种表示，并在一定条件下混合。

因此，当前 Hybrid 管线的核心不是“全局距离带 blend”，而是“对象级 route + 多信号合成”。

### 7.2 route 设计

当前系统只保留三种正式 route：

- `Blend`
- `MeshOnly`
- `VoxelOnly`

route 数据被写入 `GeometryInstanceData.flags`，定义在：

- `Source/Falcor/Scene/SceneTypes.slang`

默认情况下，`Blend = 0`，这样老数据在未显式设置 route 时也会默认落到 hybrid 路径中。

route 的写入和消费链路是统一的：

- CPU 侧或 Python 脚本设置实例 route。
- Scene 侧把 route 存进实例数据。
- Mesh debug、BlendMask、Composite 和 Voxel traversal 都从这份 scene data 读取 route。

### 7.3 Hybrid 图的组织方式

`scripts/Voxelization_HybridMeshVoxel.py` 中的 Hybrid RenderGraph 大致为：

- `MeshGBuffer`
- `MeshStyleDirectAOPass`
- `HybridBlendMaskPass`
- `VoxelizationPass`
- `ReadVoxelPass`
- `RayMarchingDirectAOPass`
- `HybridCompositePass`
- `ToneMapper`

它体现出的设计思想是：

- Mesh 与 Voxel 两条链路可以分别独立运行。
- Hybrid 阶段不是重新实现一套渲染器，而是复用两条正式链的结果。
- Composite 阶段负责做最终融合与调试输出。

### 7.4 第一阶段：基于距离的混合

系统最初的混合方式是：

- `HybridBlendMaskPass` 根据像素世界坐标到摄像机的距离，计算一个 mesh weight。
- 在近处更偏向 Mesh，在远处更偏向 Voxel。

这种方式很直观，但问题也明显：

- 它默认屏幕上所有对象都遵循同一套距离切换逻辑。
- 它无法表达“某个对象必须只走 Mesh”或“某个对象必须只走 Voxel”。
- 它无法保证非 blend 对象不支付另一条正式路径的成本。

因此，这部分在论文里最好写成“初版方案”或“基础混合策略”，而不是最终答案。

### 7.5 第二阶段：对象级 route-aware mask

在 plan5 中，`HybridBlendMaskPass` 被改成 route-aware：

- 对 `MeshOnly`，直接给 1。
- 对 `VoxelOnly`，直接给 0。
- 对 `Blend`，再按距离计算渐变权重。

也就是说，距离信息不再是唯一标准，而只是 `Blend` 类对象的一个基础信号。

### 7.6 第三阶段：对象级 Composite

当前 `HybridCompositePass` 的逻辑是这篇论文最值得写清楚的部分之一。

它不再简单按距离直接 `lerp(meshColor, voxelColor)`，而是引入了以下判据：

- Mesh route
- Mesh depth
- Voxel depth
- Voxel confidence
- Mesh instance ID
- Voxel dominant instance ID
- object match / object mismatch

最终逻辑可以概括为：

1. `MeshOnly`
   只取 Mesh 结果。

2. `VoxelOnly`
   只取 Voxel 结果。

3. `Blend`
   只有在对象身份匹配、深度差足够小、体素置信度足够高时，才允许 voxel 参与混合；否则保守退回 Mesh。

这可以写成：

“本文将混合渲染从单纯的距离插值，提升为结合对象身份、几何深度和体素置信度的对象级复合策略，从而减少跨对象误混、边缘错混和低置信度体素带来的伪影。”

### 7.7 调试输出与正确性验证

当前 Hybrid 管线额外提供了多个重要调试视图：

- `RouteDebug`
- `BlendMask`
- `VoxelDepth`
- `VoxelNormal`
- `VoxelConfidence`
- `VoxelRouteID`
- `VoxelInstanceID`
- `ObjectMismatch`
- `DepthMismatch`

这些视图的存在非常重要，因为它们说明当前工作不是“凭肉眼调一张漂亮图”，而是在系统性验证：

- route 是否真的传到了像素级。
- Mesh 与 Voxel 是否命中了同一对象。
- 深度是否一致。
- 哪些区域的体素身份不可靠。

论文中可以把这部分写成“实验与调试框架”，体现出你不是单纯做效果，而是在搭一个可验证的研究原型。

### 7.8 第四阶段：selective execution 的尝试

当前已经做了 selective execution 的结构性实现：

- Mesh 正式链通过 `instanceRouteMask` 过滤 `VoxelOnly` 对象。
- Voxel 正式链在命中阶段根据 dominant instance route 跳过 `MeshOnly` voxel。

但这里要老实写清楚：

- 这代表“结构性 selective execution 已接入”。
- 不代表“性能问题已经完全解决”。

主要原因是：

- Voxel 路径仍是 hit-level 过滤，而不是 route-aware block-level 过滤。
- 默认场景中很多对象仍为 `Blend`。
- 某些 view mode 本身是调试模式，会故意放宽 route mask 以便观察完整源图。

所以论文里更安全的写法是：

“本文进一步尝试在正式执行层面引入对象级 route 过滤，但当前实现仍未完全消除双路径并行带来的残余成本，因此其主要意义在于验证执行层面优化的方向，而非给出最终性能收敛结果。”

### 7.9 混合渲染方案的意义与局限

意义：

- 证明了体素结果可以不是独立的第二张图，而是可与 Mesh 形成对象级组合。
- 证明了对象身份和置信度对于混合是必要信号。
- 为后续真正的 route-aware LoD 执行优化提供了代码基础。

局限：

- 当前仍属于原型验证阶段。
- 性能改进方向已经显现，但没有完全收口。
- 默认场景下双路径并行现象仍然存在，导致“视觉上在切换”和“执行上真正变轻”之间存在差距。

## 8. 如何把当前实现写进论文

### 8.1 建议的系统描述口径

推荐写法：

“本文最终实现的是一套体素 LoD 混合渲染原型系统，而不是已经完全工程化的最终优化器。系统已经完成体素化、体素直接光照、体素 AO、Mesh 对照渲染、对象级混合合成和 route-aware 执行探索，并通过实验验证了方案的视觉可行性与执行瓶颈。”

### 8.2 建议的实验结论口径

实验部分可以分成三层结论：

1. 功能层结论
   体素主线可以稳定完成直接光照与 AO，Mesh 路径可提供近景对照，Hybrid 路径可以完成对象级合成验证。

2. 视觉层结论
   引入对象身份、深度与置信度后，混合结果比单纯距离插值更稳定，错混现象减少。

3. 性能层结论
   当前实现已经说明 selective execution 应该向 route-aware draw filtering 与 route-aware voxel occupancy 发展，但现阶段仍存在双路径并行的残余成本，因此性能优势尚未完全释放。

## 9. 论文大纲建议

下面给出一个适合你当前代码状态的本科论文大纲。这个大纲的核心原则是：

- 前面强调问题背景和设计思路。
- 中间写系统实现与关键模块。
- 实验章同时写“做成了什么”和“为什么性能还没有完全达到理想目标”。
- 结论章强调原型完成和瓶颈分析，而不是硬写成最终优化成功。

### 第 1 章 绪论

建议内容：

- 研究背景
  说明高保真实时渲染、直接光照、AO 和复杂场景远景表达之间的矛盾。
- 研究意义
  说明传统 Mesh LoD 会丢失微观结构与材质表达，体素可以作为远景代理的原因。
- 国内外研究现状
  可围绕 VXGI、Voxel Cone Tracing、Appearance-Preserving Aggregation、混合渲染与 GPU-driven 渲染展开。
- 本文主要工作
  概括本文实现的几个核心模块和实验分析内容。
- 论文结构安排

本章重点句式可以是：

“本文关注的不是仅靠网格简化实现传统 LoD，而是探索体素作为远景代理时，如何在保持直接光照与 AO 表达能力的同时，与原有 Mesh 渲染路径形成混合渲染原型。”

### 第 2 章 相关技术基础

建议内容：

- Falcor 框架与 RenderGraph 组织方式
- 体素表示与体素化基本原理
- 直接光照与 AO 的基本概念
- GBuffer 与基于屏幕空间的着色数据组织
- 混合渲染与 LoD 的基本思想

本章作用是给后文实现做铺垫，不必写太深的数学推导，但要说明你为什么选这些技术。

### 第 3 章 系统总体设计

建议分节：

- 3.1 系统需求与设计目标
- 3.2 整体架构
- 3.3 体素主线、Mesh 主线与 Hybrid 主线的关系
- 3.4 数据流与关键中间量
- 3.5 调试与验证机制设计

这一章建议配一张总框架图，图中可以有三条主线：

- Voxelization / Read / RayMarching
- GBuffer / MeshStyle
- BlendMask / Composite

### 第 4 章 体素化与体素渲染实现

建议分节：

- 4.1 离线体素化流程设计
- 4.2 体素缓存的数据结构设计
- 4.3 `VoxelData` 与 `PrimitiveBSDF` 的构造
- 4.4 体素射线遍历与命中判定
- 4.5 体素直接光照实现
- 4.6 体素 AO 实现
- 4.7 体素渲染输出与调试信息

这一章是你的技术主体之一，建议把缓存格式、direct light、AO 都写进去。

### 第 5 章 Mesh 路径与混合渲染实现

建议分节：

- 5.1 Mesh GBuffer 组织方式
- 5.2 Mesh 直接光照与 AO 参考路径
- 5.3 route 的实例级表达与 Scene 侧存储
- 5.4 基于距离的初版混合策略
- 5.5 route-aware 的 BlendMask 改进
- 5.6 基于深度、对象身份和置信度的 Composite 实现
- 5.7 selective execution 的设计与当前实现边界

这一章是论文里最能体现你“不是简单叠图”的地方。

### 第 6 章 实验结果与分析

建议分节：

- 6.1 实验环境与测试场景
- 6.2 体素主线结果展示
- 6.3 Mesh 与 Voxel 的对照分析
- 6.4 Hybrid 混合结果分析
- 6.5 `RouteDebug`、`ObjectMismatch`、`DepthMismatch` 调试结果分析
- 6.6 性能测试与瓶颈分析

性能分析部分建议一定要诚实写：

- 当前系统证明了 route-aware selective execution 的必要性。
- 当前原型已经开始在 Mesh 和 Voxel 正式链上做过滤。
- 但由于默认 `Blend` 比例较高、voxel coarse block 仍非 route-aware 等原因，性能收益没有完全释放。

这样写不是减分，反而更像一个完整的研究过程。

### 第 7 章 总结与展望

建议内容：

- 总结本文完成的工作
- 总结方案的主要优点
- 说明当前未完全解决的问题
- 给出未来工作方向

未来工作方向可写：

- route-aware voxel block occupancy
- 更细粒度的远景代理结构
- 更完整的全局执行模式切换
- 更适合动态场景的体素更新机制

## 10. 每章可以直接写的重点句

### 10.1 关于系统定位

“本文实现的是一套面向体素 LoD 的混合渲染原型系统，重点在于验证体素代理在直接光照、AO 和对象级混合中的可行性。”

### 10.2 关于体素化

“与仅保存颜色或占据信息的传统体素表示不同，本文在体素缓存中保留了材质响应聚合、椭球几何拟合、投影面积函数以及对象身份与置信度等信息，为后续体素着色和混合决策提供了支撑。”

### 10.3 关于混合渲染

“本文没有将 Mesh/Voxel 混合简化为纯粹的距离插值，而是引入对象级 route、深度一致性和体素置信度，从而提高混合结果的可靠性。”

### 10.4 关于性能分析

“实验表明，当前原型已经具备对象级选择性执行的结构基础，但由于体素路径仍存在残余遍历成本，且默认场景中双路径并行现象尚未完全消除，因此性能优化效果仍需进一步收敛。”

## 11. 推荐优先参考的代码与文档

- `scripts/Voxelization_MainlineDirectAO.py`
- `scripts/Voxelization_HybridMeshVoxel.py`
- `Source/RenderPasses/Voxelization/VoxelizationPass.cpp`
- `Source/RenderPasses/Voxelization/ReadVoxelPass.cpp`
- `Source/RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang`
- `Source/RenderPasses/Voxelization/RayMarchingTraversal.slang`
- `Source/RenderPasses/Voxelization/VoxelizationShared.slang`
- `Source/RenderPasses/Voxelization/Shading.slang`
- `Source/RenderPasses/HybridVoxelMesh/MeshStyleDirectAOPass.ps.slang`
- `Source/RenderPasses/HybridVoxelMesh/HybridMeshDebugPass.ps.slang`
- `Source/RenderPasses/HybridVoxelMesh/HybridBlendMaskPass.ps.slang`
- `Source/RenderPasses/HybridVoxelMesh/HybridCompositePass.ps.slang`
- `Source/Falcor/Scene/SceneTypes.slang`
- `Source/Falcor/Scene/Scene.cpp`
- `.FORAGENT/plan5.md`
- `docs/handoff/2026-04-04_mainline_direct_ao_stage4_handoff.md`
- `docs/handoff/2026-04-05_plan5_phase4_object_composite_handoff.md`
- `docs/handoff/2026-04-05_plan5_phase5_selective_execution_handoff.md`

## 12. 最后建议

如果后续要继续写论文正文，最稳妥的顺序是：

1. 先把第 3 章系统总体设计和第 9 章论文大纲转成学校要求的章节结构。
2. 再从本文件第 4、5、6、7 节抽内容，扩写成实现章节。
3. 实验章最后单独加一个“小结”，明确说明“视觉验证已经成立，性能优化方向已经明确，但仍处于原型收口阶段”。

这样整篇论文会显得技术路径清楚、实现扎实、结论诚实，而且和你现在仓库里的实际状态是一致的。
