# 2026-04-04 Mainline DirectAO Plan3

- 当前仓库的执行计划应以 `E:\GraduateDesign\Falcor_Cp\.FORAGENT\plan3.md` 为准；兄弟目录 `E:\GraduateDesign\Falcor\.foragents\` 和仓库内旧 `plan2.md` 只适合作为研究/历史参考，否则很容易把新计划写进错误位置。
- `VoxelDirectAO*` 仍同时存在于 `CMakeLists.txt`、`VoxelizationBase.cpp` 和旧脚本里，会让全仓搜索 DirectAO 时出现两条入口；在 Stage8 清理完成前，后续 Agent 必须明确只修改 `RayMarchingDirectAO*` 主线。

