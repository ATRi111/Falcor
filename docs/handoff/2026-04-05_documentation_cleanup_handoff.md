# Documentation Cleanup Handoff

## 模块职责

收敛当前文档入口，删除已完成阶段的 plan / handoff / prompt / log 文档，并把保留文档改成以 `plan5` 为唯一计划入口的结构。

## 当前保留入口

- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan5.md`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\ai_doc_navigation.txt`
- `E:\GraduateDesign\Falcor_Cp\.FORAGENT\build_any_target_brief.txt`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-05_plan5_phase3_identity_contract_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\handoff\2026-04-04_mainline_direct_ao_stage4_handoff.md`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-05_documentation_cleanup.md`

## 清理结果

- `.FORAGENT` 只保留当前仍有用的导航、构建说明和 `plan5.md`；旧 `plan3/plan4`、过时 prompt、历史愿景文档和临时 log 已移除。
- `docs\handoff` 只保留当前 mainline baseline、当前 hybrid Phase1-3 基线，以及本轮文档整理交接；plan4 阶段 handoff、plan5 Phase1/2 单独 handoff 和过渡型 route/planning handoff 已并入现有入口后删除。
- `docs\memory` 删除了只服务于旧 plan 结构或过渡清理的规划类记录，并把文档维护规则收敛到单独 memory 文件。

## 后续维护规则

- 新阶段完成后，优先判断当前主入口文档是否还能承担入口职责；只有在模块边界真的新增时，再补新的 handoff。
- 删除旧文档前先改 `plan5.md`、导航文件和保留 handoff 的引用，再做物理删除，避免留下悬挂入口。
