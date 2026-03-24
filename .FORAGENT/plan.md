# 体素渲染直接光+AO优化方案

## 一、背景分析

### 当前状态
- **VoxelDirectAOPass** 已实现基础框架，支持：
  - 直接光采样 (随机采样 + 时域累积)
  - AO计算 (随机半球采样)
  - 5种渲染模式 (Combined/DirectOnly/AOOnly/Normal/Coverage)

### 当前问题
1. **噪点明显**：直接光和AO都依赖随机采样，需要大量帧才能收敛
2. **AO有banding风险**：但目前随机采样方式实际上无banding，只有噪点
3. **相机移动时重新收敛**：用户体验差

---

## 二、三位专家方案汇总与共识

### 渲染专家建议
| 方案 | 噪点 | 性能 | 推荐 |
|------|------|------|------|
| A-确定性遍历 | ✅无 | ✅最优 | ★★★☆ |
| B-随机+累积 | ⚠️有 | 中 | ★★☆☆ |
| **C-混合策略** | ✅极低 | 良好 | **★★★★** |

### AO专家建议
| 方案 | 噪点 | Banding | 推荐 |
|------|------|---------|------|
| 随机+累积 | ⚠️有 | ✅无 | ★★★☆ |
| 固定方向 | ✅无 | ⚠️可能 | ★★★☆ |
| **固定方向+像素抖动** | ✅无 | ✅消除 | **★★★★** |
| 预烘焙 | ✅无 | ✅无 | ★★☆☆ (改动大) |

### 集成专家发现
- VoxelDirectAOPass已基本实现
- 主要需要**优化现有算法**而非重写
- 建议提取共享shader代码(未来可选优化)

---

## 三、最终推荐方案

### 直接光照：混合策略
```
┌─────────────────────────────────────────────────────────┐
│ 点光源/方向光:    确定性遍历所有光源求和 (无噪点)      │
│ 环境贴图:         1-2 samples/pixel + 时域累积         │
│ 自发光面片:       可选开关，保持随机采样               │
└─────────────────────────────────────────────────────────┘
```

### AO：固定方向 + 像素旋转抖动
```
┌─────────────────────────────────────────────────────────┐
│ 采样方向:         8个Fibonacci半球分布方向             │
│ 消除Banding:      基于(pixel+frame)的旋转抖动          │
│ 距离衰减:         (1 - d/radius)² 二次衰减             │
│ 追踪距离:         4-8体素 (可配置)                     │
└─────────────────────────────────────────────────────────┘
```

---

## 四、实施任务清单

### Phase 1: 确定性直接光照 (优先级高)
- [ ] **task-1-1**: 在shader中添加确定性光源遍历函数
  - 新增 `evalDeterministicDirectLighting()` 函数
  - 遍历 `gScene.getLightCount()` 所有分析光源
  - 对每个光源计算visibility和BSDF贡献并求和
  
- [ ] **task-1-2**: 修改 `shadingDirect()` 支持两种模式
  - 添加 `bool useDeterministicLighting` 参数
  - 确定性模式：调用新函数
  - 随机模式：保持现有逻辑(用于环境光)

- [ ] **task-1-3**: 在VoxelDirectAOPass.cpp添加UI控制
  - 新增 `mDeterministicLighting` bool选项
  - 通过cbuffer传入shader

### Phase 2: 固定方向AO采样 (优先级高)
- [ ] **task-2-1**: 实现Fibonacci半球方向分布
  ```hlsl
  static const float3 kFibonacciDirs[8] = {
      // 预计算的8个方向
  };
  ```

- [ ] **task-2-2**: 实现像素级旋转抖动
  ```hlsl
  float calcRotationAngle(uint2 pixel, uint frame) {
      return frac(dot(pixel, float2(0.754877669, 0.569840296)) + frame * 0.618033989) * 2 * Pi;
  }
  ```

- [ ] **task-2-3**: 修改 `calcAO()` 支持固定方向模式
  - 添加 `bool useFixedDirections` 分支
  - 固定方向模式：使用旋转后的Fibonacci方向
  - 添加距离衰减计算

- [ ] **task-2-4**: 添加AO相关新参数
  - `mAOUseFixedDirs` - 使用固定方向采样
  - `mAODistanceFalloff` - 启用距离衰减

### Phase 3: 参数与UI优化 (优先级中)
- [ ] **task-3-1**: 优化默认参数
  - `aoSampleCount = 8` (固定方向模式下即为8)
  - `aoRadius = 6.0f`
  - `mDeterministicLighting = true`
  - `mAOUseFixedDirs = true`

- [ ] **task-3-2**: 添加性能模式预设
  - "Quality": 16方向AO + 确定性光照
  - "Balanced": 8方向AO + 确定性光照 (默认)
  - "Performance": 4方向AO + 确定性光照

### Phase 4: 测试与验证 (优先级高)
- [ ] **task-4-1**: 编译验证
  - 构建Voxelization插件
  - 确保无编译错误

- [ ] **task-4-2**: 功能测试
  - 加载场景 + 体素缓存
  - 测试各DrawMode
  - 对比新旧AO效果

- [ ] **task-4-3**: 性能测试
  - 对比优化前后帧率
  - 确认噪点消除效果

### Phase 5: 可选优化 (优先级低)
- [ ] **task-5-1**: 提取共享shader代码
  - 创建 `VoxelTraversal.slang` 共享文件
  - RayMarching.ps.slang和VoxelDirectAO.ps.slang共用

- [ ] **task-5-2**: 环境光SH预计算 (可选)
  - 预计算场景环境光的SH系数
  - 运行时直接查询，避免采样噪点

---

## 五、关键代码修改指南

### 5.1 Fibonacci方向生成 (VoxelDirectAO.ps.slang)

```hlsl
// 预计算8个Fibonacci半球方向
static const float3 kFibonacciDirs[8] = {
    normalize(float3(0.000000, 0.000000, 1.000000)),
    normalize(float3(0.526570, 0.000000, 0.850130)),
    normalize(float3(0.159490, 0.500950, 0.850710)),
    normalize(float3(-0.427510, 0.309020, 0.849730)),
    normalize(float3(-0.427510, -0.309020, 0.849730)),
    normalize(float3(0.159490, -0.500950, 0.850710)),
    normalize(float3(0.688190, 0.499960, 0.526570)),
    normalize(float3(-0.262870, 0.809010, 0.526570)),
};
```

### 5.2 旋转抖动函数

```hlsl
float calcJitterAngle(uint2 pixel, uint frameIndex)
{
    // 黄金比例抖动，每帧每像素不同
    float pixelHash = frac(dot(float2(pixel), float2(0.754877669, 0.569840296)));
    return frac(pixelHash + frameIndex * 0.618033989) * 2.0 * Pi;
}

float3 rotateAroundZ(float3 dir, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float3(dir.x * c - dir.y * s, dir.x * s + dir.y * c, dir.z);
}
```

### 5.3 改进的calcAO函数

```hlsl
float calcAO_FixedDirs(HitResult hit, uint offset, float3 viewDir, uint2 pixel, uint frame)
{
    if (!aoEnabled || aoRadius <= 0 || aoStrength <= 0)
        return 1;

    PrimitiveBSDF bsdf = gBuffer[offset];
    float3 mainNormal = bsdf.surface.getMainNormal(viewDir);
    float3 t, b;
    buildTBN(t, b, mainNormal);

    float3 from = hit.cell + shadowBias * mainNormal;
    float jitter = calcJitterAngle(pixel, frame);

    float visibility = 0;
    float totalWeight = 0;
    
    for (int i = 0; i < 8; i++)
    {
        float3 localDir = rotateAroundZ(kFibonacciDirs[i], jitter);
        float3 worldDir = localToWorld(localDir, t, b, mainNormal);
        float weight = localDir.z; // 余弦权重
        
        HitResult aoHit = rayMarching(from, worldDir, aoRadius, true);
        
        if (!aoHit.hit) {
            visibility += weight;
        } else {
            // 距离衰减：越近遮蔽越强
            float hitDist = length(aoHit.cell - from);
            float falloff = saturate(1 - hitDist / aoRadius);
            falloff = falloff * falloff; // 二次衰减
            visibility += weight * (1 - falloff);
        }
        totalWeight += weight;
    }

    float ao = visibility / totalWeight;
    return lerp(1.0f, ao, saturate(aoStrength));
}
```

### 5.4 确定性直接光照函数

```hlsl
float3 evalDeterministicDirectLighting(HitResult hit, uint offset, float3 viewDir)
{
    PrimitiveBSDF bsdf = gBuffer[offset];
    float3 posW = gridMin + hit.cell * voxelSize;
    float3 result = 0;

    // 遍历所有分析光源
    uint lightCount = gScene.getLightCount();
    for (uint i = 0; i < lightCount; i++)
    {
        LightData light = gScene.getLight(i);
        
        float3 lightDir;
        float3 lightColor;
        float distance;
        
        // 根据光源类型计算
        if (light.type == LightType::Point)
        {
            float3 toLight = light.posW - posW;
            distance = length(toLight);
            lightDir = toLight / distance;
            float attenuation = 1.0 / (distance * distance);
            lightColor = light.intensity * attenuation;
        }
        else if (light.type == LightType::Directional)
        {
            lightDir = -light.dirW;
            distance = -1; // 无限远
            lightColor = light.intensity;
        }
        else
        {
            continue; // 跳过其他类型
        }

        // 可见性检测
        float3 mainNormal = bsdf.surface.getMainNormal(lightDir);
        float visibility = calcLightVisibility(hit, lightDir, mainNormal, distance / voxelSize.x);
        
        if (visibility > 0)
        {
            // BSDF评估
            float3 h = normalize(lightDir + viewDir);
            result += visibility * evalBSDF(offset, lightDir, viewDir, h, lightColor);
        }
    }

    return result;
}
```

---

## 六、预期效果

| 指标 | 优化前 | 优化后 |
|------|--------|--------|
| 直接光噪点 | 明显（需50+帧收敛） | 无（点光/方向光）/ 极低（环境光） |
| AO噪点 | 明显 | 无（使用固定方向+抖动） |
| AO Banding | 无 | 无（像素抖动消除） |
| 相机移动 | 重新收敛 | 即时稳定 |
| 帧率 | 基准 | 略优（减少采样方差） |
| 收敛帧数 | 50-100帧 | 1-10帧（仅环境光需累积） |

---

## 七、修改文件清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `VoxelDirectAO.ps.slang` | 修改 | 添加固定方向AO、确定性光照 |
| `VoxelDirectAOPass.cpp` | 修改 | 添加新参数UI |
| `VoxelDirectAOPass.h` | 修改 | 添加新成员变量 |

---

## 八、风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| Fibonacci方向计算错误 | AO效果异常 | 使用验证过的数学公式 |
| 旋转抖动不均匀 | 出现pattern | 使用黄金比例序列 |
| 光源遍历性能 | 大量光源时变慢 | 添加最大光源数限制 |
| 距离衰减过强 | AO过暗 | 提供衰减强度参数 |

---

## 九、验证命令

```powershell
# 1. 构建
cmake --build build --target Voxelization --config Release

# 2. 运行测试
.\build\windows-vs2022\bin\Release\Mogwai.exe --script scripts\Voxelization_DirectAO.py

# 3. 测试步骤：
#    - 加载场景
#    - ReadVoxelPass 选择.bin文件 -> Read
#    - VoxelDirectAOPass 切换DrawMode测试
#    - 对比 Combined / DirectOnly / AOOnly 效果
```
