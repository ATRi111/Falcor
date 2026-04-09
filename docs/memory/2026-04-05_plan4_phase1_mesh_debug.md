# 2026-04-05 Plan4 Phase1 Mesh Debug

- 用 `Start-Process` 启动 Mogwai 做 Phase1 窗口级验收时，如果只等窗口句柄出现或只额外等几秒，`Arcade` 还可能停在 FBX/材质加载阶段，截图会整窗纯白，现象很像 mesh debug 链路没有出图。  
- 这个白窗在本轮并不是 `HybridMeshDebugPass` 接线失败，而是抓图时机过早；规避方式是等场景真正加载完后再额外留 10~12 秒，再做窗口级截图验收。
