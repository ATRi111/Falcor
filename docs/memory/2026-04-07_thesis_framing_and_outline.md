# 2026-04-07 Thesis Framing And Outline

- 当前论文最稳妥的定位不是“最终性能完全收敛的体素 LoD 系统”，而是“体素远景代理的混合渲染原型 + 实验与瓶颈分析”；这样能同时覆盖已完成实现和未完全释放的性能收益。
- 写论文技术章节时要把体素主线、Mesh 对照链和 Hybrid 验证链分开描述，特别要明确调试视图、对象级 route 和 selective execution 的边界，避免把开发态 view mode 写成最终性能模式。
