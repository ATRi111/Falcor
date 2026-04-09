# 2026-04-07 MultiBunny Voxel Floor And AutoRead

- `MultiBunny` 的 CPU voxel cache 如果继续用 `lerpNormal=False`，地面 `createQuad()` 在 `128x8x128` 低分辨率 cache 下会被体素化出错误主法线，表现成 `NormalDebug` 出现大块对角分色、`DirectOnly/Combined` 像有一大片阴影随相机视角变化；MultiBunny 相关脚本应默认用独立 cache 名并开启 `HYBRID_CPU_LERP_NORMAL=1`。
- 缺 cache 首次自生成时，`ReadVoxelPass` 自动发现新 bin 后如果无条件 `requestRecompile()`，Mogwai 这一帧可能报 `Can't fetch the output 'ToneMapper.dst'`; 只有在 `voxelCount/solidVoxelCount` 真的变化时才需要重编 graph，同布局时应直接读回。
