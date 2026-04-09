# Voxel BRDF Lobe Quantization Handoff

## 模块职责

`Voxel/ABSDF.slang` 和 `Shading.slang` 负责把每个体素内的多边形材质/法线压缩成少量 ABSDF lobes，再由 `PrimitiveBSDF::eval()` 在 `RayMarchingDirectAO` 里做 direct lighting。

## 本轮有效结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - 新增的 `FaceNormalMask`、`LightVisibilityMask` 和 `UnshadowedDirect` 调试模式表明：黑块既不主要跟 `start-inside/fallback` 法线分类对应，也不主要跟 scene visibility 分类对应。
  - `UnshadowedDirect` 仍然出现与 `DirectOnly` 基本相同的黑块，说明问题已经收敛到 `bsdf.eval()` / ABSDF 聚合，而不是阴影 ray。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Voxel\ABSDF.slang`
  - `LOBE_COUNT` 目前只有 `4`，`NormalIndex()` 把上半球法线只分到 `+X / -X / +Z / -Z` 四类；`y` 分量只参与“翻到上半球”，不参与分桶。
  - 这意味着连续曲面上的法线一旦跨过 `|x|` 和 `|z|` 的分界，就会突然换桶，进而让 `Shading.slang` 里的 `SurfaceBRDF` 在相邻体素之间切换主 lobe 和 BRDF 响应。

## 代码定位

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Voxel\ABSDF.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\Shading.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAOPass.cpp`

## 当前调试模式

- `FaceNormalMask`
  - green=`implicit~=1`
  - blue=`implicit<1`
  - red=`fallback`
- `LightVisibilityMask`
  - green=`visible`
  - cyan=`receiverIgnored`
  - blue=`sameObjectSkipped`
  - red=`blockedOther`
  - orange=`blockedSameObject`
  - magenta=`silhouetteRescued`
- `UnshadowedDirect`
  - 绕过 scene visibility，直接输出 `lightColor * bsdf.eval(...)`

## 下一步修法建议

- 优先修 `ABSDF` 分桶而不是继续调 shadow bias：
  - 最小验证方案：先把 `LOBE_COUNT` / `NormalIndex()` 从当前 4 个 `XZ` 桶扩到能区分 `Y` 的 6 桶或更细方向桶，再看 `UnshadowedDirect` 黑块是否明显收敛。
  - 如果不想立刻改数据布局，次优方案是在 direct-lighting 上临时绕过多 lobe 聚合，用更连续的运行时法线/面法线做一个简化 diffuse 响应，只用于验证“块状暗斑是否来自 lobe quantization”。
