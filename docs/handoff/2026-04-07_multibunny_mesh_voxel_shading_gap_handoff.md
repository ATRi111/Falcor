# MultiBunny Mesh Voxel Shading Gap Handoff

## 模块职责

定位 `MultiBunny` 在 hybrid graph 下切 `MeshOnly` 与 `VoxelOnly` 时，兔子颜色明显不一致的原因，并把问题边界收敛到具体文件和着色语义，而不是停留在截图现象。

## 结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
  - `MeshOnly` / `VoxelOnly` 只是分别输出 `gMeshColor` 和 `gVoxelColor`；composite 没有再改色，所以颜色差异不是它造成的。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
  - mesh 路径直接使用 GBuffer 的 `diffuseOpacity/specRough` 和 mesh normal 做确定性 direct + AO，语义接近“连续三角面表面”。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
  - voxel 路径在着色前会 `bsdf.updateCoverage(viewDir, ...)`，而 `PrimitiveBSDF::eval()` 还会额外乘 `coverage * calcInternalVisibility(l)`；这会把能量继续压低，导致 `VoxelOnly` 明显比 `MeshOnly` 暗。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Voxel\ABSDF.slang`
  - voxel BRDF 不是逐像素复原原始 mesh 材质，而是把法线聚合到 4 个 lobe（`LOBE_COUNT = 4`，并且先把 `normal.y < 0` 翻到正半球）；兔子这类曲面会损失很多法线分布细节，最终高光和明暗过渡都会和 mesh 不同。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - 当前脚本默认把 `HYBRID_VOXEL_CHECK_COVERAGE`、`HYBRID_VOXEL_CHECK_VISIBILITY` 都设为开启，因此这种 darker / mottled 的 voxel 外观是当前默认设计结果，不是最近 sparse-layout 改动引入的新回归。

## 当前判断

- 这是“mesh shading” 与 “voxel aggregate shading” 的语义差异，不是 `MultiBunny` 材质没对上；`Scene\MultiBunny.pyscene` 里兔子材质本身只有一套 `baseColor/roughness`，mesh 和 voxel 都来自同一份源场景。
- 如果目标是保留当前体素语义，那颜色不可能和 mesh 完全一致；如果目标是让 `VoxelOnly` 更像 `MeshOnly`，需要主动收敛 shading model，而不只是继续调光源或 ToneMapper。

## 建议的下一步

- 做最小验证：
  - 先在运行时关闭 `HYBRID_VOXEL_CHECK_COVERAGE=0`
  - 再关闭 `HYBRID_VOXEL_CHECK_VISIBILITY=0`
  - 看 `VoxelOnly` 是否明显向 `MeshOnly` 靠拢，用来确认哪一项贡献最大。
- 如果要修：
  - 方案一：给 voxel 路径加一个 parity/debug 模式，跳过 `coverage/internalVisibility`，只保留和 mesh 尽量一致的 direct + AO。
  - 方案二：保留当前 voxel physically-aggregate 语义，但把 `MeshOnly` / `VoxelOnly` 的 UI 文案明确区分成“mesh source” 与 “voxel source”，避免用户把它理解成应该同色的两种等价显示。

## 后续继续时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\HybridCompositePass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\HybridVoxelMesh\MeshStyleDirectAOPass.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Voxel\ABSDF.slang`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
