# MultiBunny Voxel Floor And AutoRead Fix Handoff

## 模块职责

修复 `MultiBunny` voxel-only / blend 入口的两个问题：`ReadVoxelPass` 在缺 cache 首次自生成后的自动读回不再触发 `ToneMapper.dst` 启动报错，同时 MultiBunny 默认改为生成和读取一份启用 `lerpNormal` 的新 cache，消掉地面随视角变化的大块假阴影。

## 当前状态

- `E:\GraduateDesign\Falcor_Cp\Source\RenderPasses\Voxelization\ReadVoxelPass.cpp`
  - `tryQueueAutoBinFile()` 现在会先比较当前 grid layout 和新 bin header；只有 `voxelCount` 或 `solidVoxelCount` 变化时才 `requestRecompile()`。
  - 对“同 scene、同分辨率、首次 auto-generate 完成后自动读回”这条路径，会直接继续读文件，不再把 Mogwai 推到 `Can't fetch the output 'ToneMapper.dst'`。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_HybridMeshVoxel.py`
  - 新增 `HYBRID_CPU_SCENE_NAME` 环境变量入口，让 scene-specific 脚本可以显式控制 CPU voxel cache 文件名前缀，而不是永远写 `Auto` / 原 scene 名。
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelOnly.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_MultiBunny_VoxelRoute.py`
- `E:\GraduateDesign\Falcor_Cp\scripts\Voxelization_VoxelBunny_Blend.py`
  - MultiBunny 相关入口统一切到：
    - `HYBRID_SCENE_HINT=MultiBunnyLerp`
    - `HYBRID_CPU_SCENE_NAME=MultiBunnyLerp`
    - `HYBRID_VOXEL_CACHE_FILE=resource\\MultiBunnyLerp_(128, 8, 128)_128.bin_CPU`
    - `HYBRID_CPU_LERP_NORMAL=1`
  - 这样旧的 `MultiBunny_(128, 8, 128)_128.bin_CPU` 不会继续把错误地面法线带回默认入口。

## 根因结论

- 用户截图里 voxel-only 地面的大块“阴影”不是 `RayMarchingDirectAO` 的 direct-light / visibility 回归主因。
- 对照验证表明：用同一 scene 重新生成 `lerpNormal=1` 的 cache 后，地面对角线阴影直接消失，说明根因在 `MultiBunny` 低分辨率 CPU voxel cache 的法线/payload 生成，而不是 `DirectOnly` 专属阴影分支。

## 验证

- 构建通过：
  - `tools\.packman\cmake\bin\cmake.exe --build build\windows-vs2022 --config Release --target Voxelization Mogwai`
- Python 语法检查通过：
  - `scripts\Voxelization_HybridMeshVoxel.py`
  - `scripts\Voxelization_MultiBunny_VoxelOnly.py`
  - `scripts\Voxelization_MultiBunny_VoxelRoute.py`
  - `scripts\Voxelization_VoxelBunny_Blend.py`
- 首次缺 cache 启动验证通过：
  - `scripts\Voxelization_MultiBunny_VoxelOnly.py` 在 `resource\MultiBunnyLerp_(128, 8, 128)_128.bin_CPU` 缺失时可稳定运行并生成新 cache，`stderr` 为空，不再出现 `Can't fetch the output 'ToneMapper.dst'`。
- 窗口级结果：
  - 原始问题复现图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multibunny_voxelonly_baseline.png`
  - `lerpNormal=1` 对照图：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multibunny_voxelonly_lerpnormal.png`
  - 当前默认入口结果：`E:\GraduateDesign\Falcor_Cp\.FORAGENT\validation\multibunny_voxelonly_final.png`

## 后续继续时优先看

- 如果后面还要改 MultiBunny 的 voxel 分辨率 / sample frequency，记得同步改这三个脚本里的新 cache 文件名，否则会再次读回旧 bin。
- 如果别的 scene 也要做“同场景多份 cache 变体并存”，优先复用 `HYBRID_CPU_SCENE_NAME`，不要再把旧 cache 名覆盖回去。
- 如果以后再次看到缺 cache 首启时报 `ToneMapper.dst`，先查 `ReadVoxelPass.cpp` 里 auto-read 是否又恢复成无条件 `requestRecompile()`。
