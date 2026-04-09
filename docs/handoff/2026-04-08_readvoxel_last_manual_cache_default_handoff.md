# ReadVoxel Last Manual Cache Default Handoff

## 模块职责

让所有带 `ReadVoxelPass` 的入口默认读取“最近一次手动点击 `Read` 的 cache”，避免脚本/launcher 每次又把默认值拉回旧 bin。

## 本轮落地

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
  - 启动时先检查 `resource/.readvoxelpass_last_manual_cache.txt`，若存在且文件有效，就优先把它作为 `mAutoBinFile`，覆盖脚本传入的默认 `binFile`。
  - 用户在 UI 里手动点 `Read` 后，会把当前选中的 cache 文件名写回这个状态文件。
  - 新增日志 `ReadVoxelPass: auto-reading cache '...'`，用于确认真正读到的是哪一个 bin。
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.h`
  - 增加最近手动 cache 和 UI 选择初始化状态的成员，避免 dropdown 每帧被强制重置。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - 日志里的 `voxel cache` 改为打印 `read_bin_file`，减少脚本层和实际 `ReadVoxelPass` 读入路径不一致时的误导。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Mesh.bat`
- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
- `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
  - 默认 scene/cache 已切到 `MultiMultiBunny` 的 `512` cache，减少首次启动就落回旧 `128` 配置的概率。

## 验证

- 编译通过：
  - `cmake --build build/windows-vs2022 --config Release --target Voxelization Mogwai --parallel 8`
- 用显式 `128` 脚本环境 + 手工写入的最近手动 cache 记录做覆盖验证后，stdout 已打印：
  - `ReadVoxelPass: auto-reading cache 'E:\GraduateDesign\Falcor_Cp\resource\MultiMultiBunny_(512, 41, 499)_512.bin_CPU'.`

## 后续优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `E:\GraduateDesign\Falcor_Cp\resource\.readvoxelpass_last_manual_cache.txt`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
