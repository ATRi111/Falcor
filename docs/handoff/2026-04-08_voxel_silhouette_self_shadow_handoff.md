# Voxel Silhouette Self Shadow Handoff

## 模块职责

继续排查 hit-face-normal 修完后仍残留的 voxel 黑边，把问题从“法线可视化”进一步收敛到 direct-light 的 view-grazing self-shadow，并在 `RayMarchingDirectAO` 里加一层更针对 silhouette 的抑制。

## 根因结论

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - residual 黑边不主要来自 AO；在同一机位把 direct-light 的 `visibility` 临时强制成 `1` 后，近景 bunny silhouette 会明显变干净，说明 artifact 主要来自 `calcLightVisibility()` 这一层的 scene visibility。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
  - 旧逻辑只靠 `hit.cell + shadowBias * mainNormal` 起步，再做一次普通 ray marching；对 view-grazing 的 voxel surface 来说，这很容易把同物体邻近体素当成遮挡物，表现成黑边随相机角度变化。

## 本次改动

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
  - 新增 `calcSceneLightVisibility()`，在 direct-light shadow ray 上加入两层 receiver-side 抑制：
    - 近接收点沿 `lightDir` 的 `receiverIgnoreDistance`
    - 对同一 `dominantInstanceID` 的近距离命中做有限次 skip
  - direct lighting 在拿到 `visibility` 后，再按 `faceNormal` 对 `viewDir` 的掠射程度做 `silhouetteFade`，只对接近 silhouette 的像素把 visibility 往 `1` 拉，避免整景去阴影。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
  - 回退到原始通用 `calcLightVisibility()`；这轮修正只保留在 `RayMarchingDirectAO` 本地，不把 heuristic 扩散到旧 `RayMarching.ps.slang` 或别的 pass。

## 验证

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization Mogwai`
- 近景抓图对照：
  - 基线 direct-only：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_debug_directonly_close.png`
  - 关闭 scene visibility 的诊断图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_debug_directonly_close_novis.png`
  - 当前 silhouette/self-shadow 修正图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_debug_directonly_close_silhouettefade_fixed.png`

## 后续继续时优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingDirectAO.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingTraversal.slang`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_debug_directonly_close.png`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_debug_directonly_close_novis.png`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\voxel_debug_directonly_close_silhouettefade_fixed.png`

## 注意

- 这轮仍是 heuristic 修法，不是严格几何可见性重建；如果用户机位下还剩少量黑边，下一步优先把 `sameObjectIgnoreDistance` / `silhouetteFade` 做成可调参数，而不是重新回到 cache 或 AO 链路。
