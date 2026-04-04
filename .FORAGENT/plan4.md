# plan4：mesh + voxel 混合渲染设计与实施计划

## 1. 文档定位

- 本文件是下一阶段渲染方案的设计文档和实施计划，不是“立刻开始写 mesh 渲染代码”的指令。
- 当前可验收基线仍然是 Stage4 的 voxel 主线；在 plan4 的各阶段真正验证通过前，不要替换这条基线。
- plan4 的目标是给后续 Agent 一个可执行的实施路径，让它知道先看哪里、先做什么、每一步怎样判定通过。

## 2. 目标与非目标

### 目标

- 近景使用 mesh 渲染。
- 远景和更粗的 LOD 继续使用现有 voxel 方案。
- 中景同时允许 mesh 和 voxel 共存，并通过平滑混合完成过渡。
- mesh 路径的 direct lighting 和 AO 要尽量贴近当前 voxel 主线的视觉结果，避免切换区穿帮。

### 非目标

- 本轮不直接实现完整 hybrid 渲染。
- 本轮不要求一次性决定所有 shader 细节或最终性能策略。
- 本轮不要求替换当前 `.bin` cache 流程，也不要求重写现有 `RayMarchingDirectAO*` 主线。

## 3. 当前基线

### 当前主线

当前仓库的实际展示基线是：

- `scripts\Voxelization_MainlineDirectAO.py`
- `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`

当前主线已经提供：

- 基于 cache 的 voxel 读取和稳定出图链路。
- 确定性的 direct lighting。
- Stage4 的稳定 AO baseline。
- 以 Mogwai 实际窗口画面为准的可展示结果。

### 当前体素方案擅长什么

- 远景和整体结构稳定，噪点少，画风统一。
- 基于 cache 的读取路径明确，当前主线调试入口清晰。
- direct + AO 的视觉口径已经稳定，适合当作后续 mesh 对齐目标。

### 当前体素方案不擅长什么

- 近景几何细节、轮廓、接触边界和材质细节表达受限。
- 当相机更靠近表面时，voxel 近景细节很容易显得粗或硬。
- 单一路径同时覆盖近景和远景时，细节和成本的取舍空间有限。

### 为什么需要 mesh + voxel 混合

- 近景需要 mesh 的几何和材质表达能力。
- 远景继续用 voxel 更稳，且能延续当前已有链路。
- 中景不能硬切；如果两套结果风格不一致，移动相机时会立刻穿帮。

## 4. 设计原则

- 视觉一致性优先于单条路径局部最优。
- 混合区必须平滑过渡，不能只靠单一距离阈值硬切。
- mesh direct lighting 必须尽量复用或对齐 voxel 的光照口径，不允许做成明显不同的一套风格。
- mesh AO 必须尽量贴近当前 voxel AO 的接触暗化、整体强度和空间尺度。
- 近景、中景、远景都必须走同一套 tone mapping 和 background 口径，不能各自独立收尾。
- 不要把 mesh 逻辑直接堆进 `RayMarchingDirectAOPass`；hybrid 方案应有独立组织层。

## 5. 建议的数据流与 pass 架构

### 5.1 总体思路

建议把 hybrid 方案拆成三条子链路：

1. voxel 子链路
2. mesh 子链路
3. 中景混合与最终合成子链路

最终合成应在 tone mapping 之前完成，所有路径先在同一线性空间汇合，再交给同一个 `ToneMapper`。

### 5.2 voxel 子链路

继续复用当前主线：

- `ReadVoxelPass`
- `RayMarchingDirectAOPass`

但为了给中景混合提供足够信号，后续可能需要让 voxel 路径额外输出：

- `voxelColor`
- `voxelDirect`
- `voxelAO`
- `voxelDepth` 或 `voxelHitT`
- `voxelNormal`
- `voxelCoverage` 或 `voxelConfidence`

这里的关键不是立刻实现，而是明确：如果只有一张最终 color，后续很难做稳定的中景 blend。

### 5.3 mesh 子链路

建议优先基于现有 Falcor pass 搭建，不要先自写整套底层：

- 近景 mesh 可先尝试 `GBufferRaster`
- 如果后续发现某些几何、材质或 hit 信息更适合 ray-traced visibility，再评估 `VBufferRT`

建议新增的 mesh 侧 pass：

- `MeshVisibilityPass` 或直接复用 `GBufferRaster`
- `MeshStyleDirectAOPass`

mesh 路径至少应输出：

- `meshDepth`
- `meshPosW`
- `meshNormalW`
- `meshMaterial` 或足够的 shading 属性
- `meshDirect`
- `meshAO`
- `meshColor`
- `meshStabilityMask` 或 `meshValidity`

### 5.4 中景混合子链路

建议新增两个明确职责的阶段：

1. `HybridBlendMaskPass`
   - 负责生成 `meshWeight / voxelWeight`
   - 输入应包括距离带、mesh depth、voxel hit depth、coverage/confidence、可选 hysteresis/stability mask

2. `HybridCompositePass`
   - 负责按权重在同一线性空间合成 `meshColor` 与 `voxelColor`
   - 必要时也能分别对 `direct` 和 `AO` 做调试输出

### 5.5 中景 blend 建议信号

中景 blend 不建议只靠单一距离值。建议至少组合以下信号：

- 相机到表面的距离区间
- mesh 与 voxel 的深度是否一致
- voxel 命中覆盖度或置信度
- mesh 是否有效命中
- 稳定 mask 或 hysteresis，避免相机轻微移动就来回抖动

推荐的工程化做法：

- 先用距离带给出一个基础权重。
- 再用深度差、coverage/confidence 做修正。
- 对最终权重做轻量稳定化，避免在边界像素上闪动。

### 5.6 文件与目录建议

后续 hybrid 相关逻辑建议单独落在新目录，而不是继续挤进 `Voxelization` 主线：

- 建议新建 `Source\RenderPasses\HybridVoxelMesh\`
- 当前 voxel 主线仍保留在 `Source\RenderPasses\Voxelization\`
- 共享的光照/AO helper 如果需要复用，再抽成公共 `.slang` include

建议优先查看的现有源码：

- `Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
- `Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- `Source\RenderPasses\GBuffer\VBuffer\VBufferRT.cpp`
- `Source\RenderPasses\ToneMapper\ToneMapper.cpp`
- `scripts\Voxelization_MainlineDirectAO.py`

## 6. 视觉对齐策略

### 6.1 mesh direct 如何贴近当前 voxel direct

- 优先使用与 voxel 路径一致的 analytic light 范围：先对齐 point light 和 directional light。
- 优先复用同一套能量口径、阴影倾向和 fallback 策略，而不是让 mesh 路径单独发明一套更写实或更亮的 direct。
- 如果需要提取共用 helper，优先把 direct lighting 的求和和 light-type 处理从 `RayMarchingDirectAO.ps.slang` 抽到共享 include。
- shadow bias 的语义要统一。mesh 路径可以换成 world-space bias，但最终视觉上必须和 voxel 路径的偏移倾向一致。

### 6.2 mesh AO 如何贴近当前 voxel AO

- 第一版 mesh AO 不要做成常见屏幕空间 SSAO 风格，否则中景混合时会立刻看出两套 shading。
- 优先模仿当前 voxel 的 `contactAO + macroAO` 分层思路。
- 采样方向也要保持稳定，禁止把 `frameIndex` 随机重新引入到 mesh AO。
- 如果需要空间打散，优先使用 world-space cell、triangle/primitive id 或稳定 hash，而不是时间随机。

### 6.3 统一口径的项目

以下项目应由 hybrid 方案统一管理，不应让 mesh 和 voxel 各自为政：

- tone mapping
- background / miss 背景
- shadow bias 调参方法
- AO 强度和半径的标定口径
- debug 视图的输出空间

### 6.4 混合区避免穿帮的原则

- 混合应在 pre-tonemap 的线性空间完成。
- 不允许一边先 tone map、另一边还在线性 HDR，再做混合。
- mesh 和 voxel 的 direct/AO 分量都应能单独查看，否则很难判断到底是哪一部分造成“更亮、更灰、更硬”。
- 如果混合区里出现“一个更亮、一个更灰、一个更硬”，优先先调对齐，不要先扩大 blend 区掩盖问题。

## 7. 分阶段实施建议

### 7.1 Phase0：建立对齐基线

#### 目标

冻结当前 Stage4 voxel 基线，并整理后续对齐必须使用的参考视角和截图。

#### 主要改动区域

- 文档和脚本层为主
- `scripts\Voxelization_MainlineDirectAO.py`
- 当前 stage4 handoff / memory 文档

#### 风险

- 没有固定参考视角时，后续 mesh 对齐会变成“凭印象调图”。

#### 通过条件

- 至少整理出近景、中景、远景各一组参考视角。
- 每组都保留 Mogwai 窗口截图与参数记录。

### 7.2 Phase1：搭起 mesh 可见性与调试链路

#### 目标

先建立 mesh 单独出图能力，不做 blend，只确认近景 mesh 的 depth / normal / material / color 调试链路完整。

#### 主要改动区域

- 新脚本，建议命名为 `scripts\Voxelization_HybridMeshVoxel.py`
- `Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
- 或在必要时评估 `Source\RenderPasses\GBuffer\VBuffer\VBufferRT.cpp`
- 新建 hybrid pass 目录骨架

#### 风险

- 近景 mesh 路径一开始就选错输入契约，后面 direct/AO 难以对齐。

#### 通过条件

- 能稳定输出 mesh depth / normal / base shading debug 图。
- Mogwai 中可以单独切换查看 mesh-only 路径。

### 7.3 Phase2：mesh deterministic direct 对齐

#### 目标

让 mesh 路径先在 `DirectOnly` 上尽量靠近当前 voxel 主线。

#### 主要改动区域

- 新增 `MeshStyleDirectAOPass`
- 共享 direct lighting helper 的抽取或复用
- hybrid 调试脚本

#### 风险

- mesh direct 一旦比 voxel 更亮、更硬或阴影边缘完全不同，中景 blend 还没开始就已经注定穿帮。

#### 通过条件

- 在近景参考视角下，mesh `DirectOnly` 与 voxel 基线的亮暗分区接近。
- 不能出现明显不同的一套主光风格。

### 7.4 Phase3：mesh AO 对齐

#### 目标

让 mesh AO 的接触暗化、整体强度和稳定性尽量靠近当前 voxel AO。

#### 主要改动区域

- `MeshStyleDirectAOPass`
- 可能新增共享 AO helper 或配置结构

#### 风险

- 如果 mesh AO 做成通用 SSAO 风格，会在混合区形成“mesh 更灰、voxel 更块状”的双重风格冲突。

#### 通过条件

- 近景 `AOOnly` 和 `Combined` 在静止与缓动镜头下都稳定。
- 与 voxel 基线相比，没有明显更灰或更重的 AO 风格漂移。

### 7.5 Phase4：引入中景 blend 与 hybrid 合成

#### 目标

实现“近景 mesh、远景 voxel、中景 blend”的第一版完整链路。

#### 主要改动区域

- `HybridBlendMaskPass`
- `HybridCompositePass`
- 可能需要扩展 voxel pass 输出 `depth / normal / confidence`
- 新 hybrid graph 脚本

#### 风险

- 只靠距离阈值会导致明显硬切。
- mesh 与 voxel 深度不一致时容易出现空洞、重影或双重遮蔽。

#### 通过条件

- 相机穿越 blend 区时没有明显 pop。
- 中景不会突然变亮、变黑或跳成另一套画风。

### 7.6 Phase5：稳定性与性能收敛

#### 目标

对 blend mask、LOD 区间、输出分量和 pass 成本做收敛，保证方案可持续维护。

#### 主要改动区域

- blend/composite pass
- hybrid graph
- 可能涉及 voxel 和 mesh 路径的输出裁剪

#### 风险

- 为了省成本砍掉关键调试信号，后续再出问题时难以定位。
- 为了追求平滑而把 blend 区做得过宽，导致中景长期处于“两套结果叠加”的不稳定状态。

#### 通过条件

- blend 区宽度、阈值和稳定化策略有明确默认值。
- 成本可接受，调试入口仍然保留。

## 8. 验证方案

### 近景

- 重点看 mesh 细节是否明显优于 voxel 近景。
- 重点看 mesh direct / AO 是否贴近 voxel 基线风格，而不是另起一套 look。

### 中景

- 重点看 blend 是否平滑。
- 重点看 mesh 和 voxel 在中景是否出现颜色、灰度、阴影硬度上的突变。

### 远景

- 重点看是否仍由 voxel 主线稳定支撑，不因 hybrid 引入新的闪烁或背景问题。

### 穿越 blend 区

- 相机前后移动穿越 blend 区时，要专门看：
  - 是否突然变亮
  - 是否突然变黑
  - 是否边缘硬切
  - 是否出现明显风格跳变
  - 是否出现空洞、双边、重影

### 验收规则

- 验收以 Mogwai 窗口截图和实际画面为准。
- 不以离屏导图、缓存图或单独导出的中间结果作为最终验收依据。

## 9. 风险与开放问题

- mesh 与 voxel 的几何定义不一致时，中景深度和遮蔽可能无法自然对齐。
- mesh AO 与 voxel AO 的半径、强度、法线语义可能天然不同，需要额外标定。
- blend 区越宽，越容易稳定；但越宽也越容易暴露两套 shading 的差异。
- `GBufferRaster` 与 `VBufferRT` 哪条更适合作为 mesh 第一版主路径，后续需要结合场景和材质需求确认。
- 如果 voxel 路径不能提供足够的深度/法线/置信度信号，blend 只能做成脆弱的颜色插值。
- pass 数量、调试信号和维护复杂度会上升，必须控制拆分边界，避免每个问题都新开一条路径。

## 10. 后续 Agent 优先查看

1. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan4.md`
2. `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md`
3. `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_handoff.md`
4. `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_cleanup_handoff.md`
5. `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MainlineDirectAO.py`
6. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
7. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`
8. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
9. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\GBuffer\GBufferRaster.cpp`
10. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\GBuffer\VBuffer\VBufferRT.cpp`
11. `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\ToneMapper\ToneMapper.cpp`
