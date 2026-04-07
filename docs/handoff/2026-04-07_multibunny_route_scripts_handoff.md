# MultiBunny Route Scripts Handoff

## 模块职责

新增一个用于密集 Bunny 场景测试的 `MultiBunny` pyscene，并围绕它整理出 MeshOnly、VoxelOnly 和 Blend 三类 Mogwai 启动入口。

## 当前状态

- `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
  - 新增了 10x10 的 Bunny 阵列、地面、相机和基础灯光。
  - Bunny 资源直接复用 `Scene\BoxBunny\Bunny.obj`，避免复制模型文件。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
  - 通过环境变量固定 `HYBRID_SCENE_PATH/HINT`。
  - 统一把所有 geometry instance route 设为 `MeshOnly`。
  - 输出走 `meshview + combined`，只看 mesh 正式链。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - 统一把所有 geometry instance route 设为 `VoxelOnly`。
  - 默认 CPU voxelization，`128` 分辨率、`128` sample frequency，并显式绑定 `resource\MultiBunny_(128, 8, 128)_128.bin_CPU`。
  - cache 缺失时可自动生成，cache 存在时可直接读回并显示 voxel 结果。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - 纯 voxel 的明确命名入口，行为与 `Voxelization_MultiBunny_VoxelRoute.py` 对齐，方便直接按需求区分 launcher。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
  - 强制所有实例 route 为 `Blend`，输出走 `Composite`。
  - 显式设置 `HYBRID_BLEND_START_DISTANCE=3.00`、`HYBRID_BLEND_END_DISTANCE=5.75`，让当前 MultiBunny 机位下能同时看到 mesh / voxel / 过渡带。
- 根目录 bat launcher：
  - `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
    当前默认指向 `MultiBunny`，支持 `mesh` / `voxel` 两种一键模式。
  - `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
    固定启动纯 voxel MultiBunny。
  - `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
    固定启动可 blend 的 VoxelBunny 入口。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - 新增 `HYBRID_FORCE_ALL_ROUTE` 支持，允许脚本级整景 route 覆写。
  - 新增稳态 repo root 解析和显式 `HYBRID_VOXEL_CACHE_FILE` 入口，避免 `__file__` 在回调阶段失效或首帧 `updatePass()` 破坏 graph 编译。

## 关键文件

- `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
- `E:\GraduateDesign\Falcor_Cp\run_HybridMeshVoxel.bat`
- `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
- `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\docs\memory\2026-04-07_multibunny_route_scripts.md`

## 运行方式

- Mesh 路由：
  `Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_MeshRoute.py --scene E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
- Voxel 路由：
  `Mogwai.exe --script E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py --scene E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`
- 纯 voxel bat：
  `E:\GraduateDesign\Falcor_Cp\run_MultiBunny_Voxel.bat`
- Blend bat：
  `E:\GraduateDesign\Falcor_Cp\run_VoxelBunny_Blend.bat`

## 验证

- 仓库完整 Release 编译通过：
  `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --parallel 8`
- Python 语法检查通过：
  - `scripts\Voxelization_HybridMeshVoxel.py`
  - `scripts\Voxelization_MultiBunny_MeshRoute.py`
  - `scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `scripts\Voxelization_VoxelBunny_Blend.py`
  - `Scene\MultiBunny.pyscene`
- Mogwai 烟测通过：
  - Mesh route 脚本可稳定运行 15~20 秒，无新增 stderr 异常。
  - Voxel route 脚本已完成 cache 生成并可稳定运行 25 秒，无 stderr 异常。
  - `Voxelization_MultiBunny_VoxelOnly.py` 可稳定运行 18 秒，无新增 stderr 异常。
  - `Voxelization_VoxelBunny_Blend.py` 可稳定运行 18 秒，无新增 stderr 异常。

## 后续继续时优先看

- 如果要改 MultiBunny 的密度、相机或灯光，先看 `E:\GraduateDesign\Falcor_Cp\Scene\MultiBunny.pyscene`。
- 如果要把“整景强制 route”扩到别的 scene，优先复用 `HYBRID_FORCE_ALL_ROUTE`，不要再复制整份 hybrid graph。
- 如果后面要改 MultiBunny 的 voxel 分辨率或 sample frequency，记得同步改 `Voxelization_MultiBunny_VoxelRoute.py` 里的显式 cache 文件名，否则 `ReadVoxelPass` 会继续盯旧 bin。
- 如果后面还要维护 bat 启动器，优先改根目录这三个文件，而不是把路径和参数散落回临时 PowerShell 命令里。
