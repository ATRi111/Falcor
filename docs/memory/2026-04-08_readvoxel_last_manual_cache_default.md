# 2026-04-08 ReadVoxel Last Manual Cache Default

- `ReadVoxelPass` 如果同时受到脚本 `binFile` 默认值和用户手动 `Read` 的影响，后续启动很容易又回退到旧 cache；现在会把最近一次手动读取的文件名持久化到 `resource/.readvoxelpass_last_manual_cache.txt`，之后优先回读它。
- 排障时不要只看 `Voxelization_HybridMeshVoxel.py` 的脚本层默认 cache；真正的默认读入优先级已经下沉到 `ReadVoxelPass.cpp`，日志里会打印实际 auto-read 的 cache 路径。
