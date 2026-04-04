# Mainline DirectAO Plan Handoff

> 此交接文档已被 `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_plan3_handoff.md` 和 `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md` 取代，保留仅供历史对照。

## 模块职责

本模块只负责“从主线 voxel 渲染链独立推导并整理 Direct Light + AO 的落地手册”，产出是可直接给后续 AI 按阶段执行的实施文档，而不是代码实现本身。

## 本轮产物

- 主计划：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan2.md`
  - 这份文件现在是执行手册，不是方案综述
- 对比参考：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan.md`
- 历史导航：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\ai_doc_navigation.txt`

## 后续 AI 应优先阅读

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan2.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\voxelization_pipeline_brief.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_GPU.py`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarchingPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\RayMarching.ps.slang`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\MixLightSampler.slang`

## 关键结论

- 最优路线不是继续往现有 `RayMarchingPass` 里堆分支，而是在同一插件里新增一个主线风格的 direct+AO pass，保持 `ReadVoxelPass` 输入契约不变。
- 直接光应优先改成 point/directional lights 的确定性遍历求和，先从源头去掉 direct lighting 的 Monte Carlo 噪点。
- AO 不建议继续走随机半球采样；优先做固定方向 AO，并在加载期生成 `OccupancyMip3D + VoxelOcclusionBuffer`，必要时再考虑扩展缓存格式。
- 环境项如果后续要保留，优先做 `bent-normal` 驱动的稳定 lookup，不要回退到随机 `sampleLight()` 主路径。
- `plan2.md` 已按阶段拆成了“先 skeleton、再 traversal、再 deterministic direct、再 fixed AO、再 AO preload 结构、最后回归”的顺序，后续 AI 不要跳阶段。

## 注意事项

- 当前工作树里已经有未提交的 `VoxelDirectAOPass` 相关文件和 Voxelization 插件改动，本轮没有修改这些现有代码，只新增了文档。
- 如果后续 AI 真正开始实现，请先确认是按 `plan2.md` 的主线方案执行，还是继续沿用仓库里现成的 `VoxelDirectAOPass` 分支实现。
