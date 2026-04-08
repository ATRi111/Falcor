# Voxel Runtime Normal Rollback Handoff

## 当前状态

体素黑边相关的 runtime normal / AO / direct-lighting 调整已经回退，不再保留在当前工作树里。现在的有效改动基线是 `ReadVoxelPass` 最近手动 cache 持久化，以及 `MultiMultiBunny 512` 的默认 launcher/script 配置。

## 继续排障前优先看

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.h`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
- `E:\GraduateDesign\Falcor_Cp\resource\.readvoxelpass_last_manual_cache.txt`

## 说明

如果后面还要重新查 voxel 黑边，不要从这轮已经回退掉的 runtime normal 方案继续接，直接从当前基线重新做最小验证。
