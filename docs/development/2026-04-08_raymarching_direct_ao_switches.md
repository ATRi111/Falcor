# RayMarching DirectAO Switches

## 目标

解释 `RayMarchingDirectAOPass` 里的三个关键开关：

- `CheckEllipsoid`
- `CheckVisibility`
- `CheckCoverage`

重点说明它们各自控制的含义、对应代码位置，以及在着色公式里的作用。

## 当前默认值

截至 `2026-04-08`，当前默认值是：

- `CheckEllipsoid = true`
- `CheckVisibility = false`
- `CheckCoverage = false`

默认值在这些位置保持一致：

- `Source/RenderPasses/Voxelization/RayMarchingDirectAOPass.cpp`
- `Source/RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang`
- `scripts/Voxelization_MainlineDirectAO.py`
- `scripts/Voxelization_HybridMeshVoxel.py`

## 整体代码链路

`RayMarchingDirectAOPass` 的关键执行路径如下：

1. `RayMarchingDirectAOPass.cpp`
   - 从 pass 属性和脚本属性读取三个开关。
   - 把它们转换成 shader define：
     - `CHECK_ELLIPSOID`
     - `CHECK_VISIBILITY`
     - `CHECK_COVERAGE`
2. `RayMarchingDirectAO.ps.slang`
   - 主像素着色器先做主射线命中。
   - 命中后读取 `PrimitiveBSDF`，计算 `coverage`、`direct lighting` 和 `AO`。
3. `RayMarchingTraversal.slang`
   - 负责 DDA / mipmap traversal、椭球裁剪、保守 fallback、场景阴影可见性。
4. `Shading.slang`
   - 负责 `PrimitiveBSDF` 的 `coverage`、内部可见性和最终 `eval()`。

把直接光部分抽象成一个式子，可以写成：

```text
L_direct = V_scene(l) * Li(l) * f_voxel(l, v, h)
```

其中：

```text
f_voxel(l, v, h) = C(v) * f_surface(l, v, h) * V_internal(l)
```

- `C(v)` 由 `CheckCoverage` 控制。
- `V_internal(l)` 由 `CheckVisibility` 控制。
- `V_scene(l)` 是场景阴影遮挡，来自 shadow ray traversal，不受 `CheckVisibility` 控制。
- `CheckEllipsoid` 不改 BRDF 项，而是改“主射线是否命中该 voxel”。

## CheckEllipsoid

### 含义

`CheckEllipsoid` 控制主射线和 shadow / probe traversal 在命中 solid voxel 后，是否继续用该 voxel 的拟合椭球做一次几何细化。

- 关闭时：只要进入一个 `solid voxel`，就视为命中。
- 打开时：还要满足射线与该 voxel 的拟合椭球相交，才算命中。

它控制的是“几何命中边界”，不是光照强度。

### 对应代码

- `Source/RenderPasses/Voxelization/RayMarchingTraversal.slang`
  - `checkPrimitive()`
  - `rayMarching_DDA()`
  - `rayMarching_Mipmap()`
  - `rayMarching()`
  - `rayMarchingConservative()`
- `Source/RenderPasses/Voxelization/Math/Ellipsoid.slang`
  - `Ellipsoid::clip()`
- `Source/RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang`
  - 主射线 miss 后的 conservative fallback

### 公式

椭球在局部坐标下定义为：

```text
x^T B x <= 1
```

线段写成：

```text
p(u) = from + u * (to - from),  u in [0, 1]
```

令：

```text
v = to - from
p0 = from - center
```

代入得到一元二次方程：

```text
a = v^T B v
b = 2 * v^T B p0
c = p0^T B p0 - 1
```

```text
a u^2 + b u + c = 0
```

判别式：

```text
d = b^2 - 4ac
```

- 若 `d < 0`，线段与椭球不相交。
- 否则求出进入和离开的参数 `uIn`、`uOut`。

这正是 `Ellipsoid::clip()` 在做的事。

### 在当前 pass 中的特殊处理

`RayMarchingDirectAO.ps.slang` 的主射线路径不是“纯 ellipsoid 命中”。它先调用正常的 `rayMarching()`；如果开启了 `CHECK_ELLIPSOID` 且 miss，再额外回退到 `rayMarchingConservative()`。

也就是：

```text
primaryHit = ellipsoid refined hit
if miss:
    primaryHit = conservative solid-voxel hit
```

这样做是为了避免某些 thin / sparse voxel 上因为椭球裁剪过严出现 pinhole。

## CheckCoverage

### 含义

`CheckCoverage` 控制“从当前观察方向看，这个 voxel 被真实几何覆盖了多少比例”。

这里不是场景阴影，也不是 AO，而是 voxel 内部对观察方向的几何覆盖率。

- 关闭时：覆盖率固定为 `1`。
- 打开时：根据投影面积比值计算 `coverage`。

### 对应代码

- `Source/RenderPasses/Voxelization/Shading.slang`
  - `PrimitiveBSDF::calcCoverage()`
  - `PrimitiveBSDF::updateCoverage()`
  - `PrimitiveBSDF::eval()`
- `Source/RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang`
  - `bsdf.updateCoverage(viewDir, transmittanceThreshold)`
  - `float coverage = bsdf.calcCoverage(viewDir);`

### 公式

在 `Shading.slang` 中，coverage 公式是：

```text
C(v) = saturate(A_polygons(v) / A_primitive(v))
```

其中：

- `A_primitive(v)` 是拟合 primitive 在方向 `v` 上的投影面积。
- `A_polygons(v)` 是实际 polygon contributor 在方向 `v` 上的可见投影面积。

代码里的对应量是：

- `primitiveProjAreaFunc.calc(direction)`
- `polygonsProjAreaFunc.calc(direction)`

### 阈值修正

`updateCoverage()` 不是简单写缓存，还会做一次阈值钳制：

```text
if 1 - C(v) < threshold:
    C(v) = 1
```

这对应代码里的：

```text
coverage = calcCoverage(direction);
if (1 - coverage < threshould)
    coverage = 1;
```

当前 `RayMarchingDirectAO.ps.slang` 在直接光计算前，会先对 `viewDir` 做这一步。

### 在着色里的作用

在 `PrimitiveBSDF::eval()` 中，表面项前面会乘上 `coverage`：

```text
f_voxel(l, v, h) = C(v) * f_surface(l, v, h) * V_internal(l)
```

如果 `coverage < 1` 且命中的是 delta transmission 分支，还会走：

```text
(1 - C(v)) * delta.eval(...)
```

所以 `CheckCoverage` 改的不只是 debug 图，而是直接参与 voxel BRDF 的能量分配。

## CheckVisibility

### 含义

`CheckVisibility` 控制的是 voxel 内部的“入射方向可见性”或“内部遮挡”。

它回答的问题是：

`光从方向 l 进入当前 voxel 时，真正能被外层 polygon 看见的比例是多少？`

它不是 shadow ray 的场景遮挡。

- 关闭时：内部可见性恒为 `1`。
- 打开时：按投影面积比值衰减入射光。

### 对应代码

- `Source/RenderPasses/Voxelization/Shading.slang`
  - `PrimitiveBSDF::calcInternalVisibility()`
  - `PrimitiveBSDF::eval()`
- `Source/RenderPasses/Voxelization/RayMarchingDirectAO.ps.slang`
  - `evalDeterministicDirectLighting()`
  - 里面调用 `bsdf.eval(lightDir, viewDir, h)`

### 公式

内部可见性公式是：

```text
V_internal(l) = saturate(A_polygons(l) / A_total(l))
```

其中：

- `A_polygons(l)` 是该方向下当前 polygon contributor 的可见投影面积。
- `A_total(l)` 是该方向下所有 polygon contributor 的总投影面积。

代码里的对应量是：

- `polygonsProjAreaFunc.calc(direction)`
- `totalProjAreaFunc.calc(direction)`

### 在着色里的作用

`PrimitiveBSDF::eval()` 的主路径是：

```text
return coverage * surface.eval(l, v, h) * calcInternalVisibility(l);
```

也就是说，`CheckVisibility` 关掉后并不会影响主射线命中，也不会影响 scene shadow，但会去掉 voxel BRDF 里的这一层内部遮挡衰减。

## CheckVisibility 和场景阴影不是同一个东西

仓库里还有另一个函数：

- `Source/RenderPasses/Voxelization/RayMarchingTraversal.slang`
  - `calcLightVisibility()`

它做的是 shadow ray traversal：

```text
V_scene(l) =
    0, if a shadow ray hits another voxel
    1, otherwise
```

代码逻辑是：

1. 从 `hit.cell + shadowBias * mainNormal` 出发。
2. 朝 `lightDir` 做一次 `rayMarching(...)`。
3. 若中途命中遮挡物，返回 `0`；否则返回 `1`。

所以 direct lighting 实际是：

```text
L_direct = V_scene(l) * Li(l) * C(v) * f_surface(l, v, h) * V_internal(l)
```

其中：

- `CheckVisibility` 只控制 `V_internal(l)`。
- `calcLightVisibility()` 控制 `V_scene(l)`。

这两者概念不同，代码位置也不同。

## getMainNormal() 在这里做什么

`SurfaceBRDF::getMainNormal(direction)` 会选权重最大的 lobe normal，并翻到与给定方向同半球。

对应代码在：

- `Source/RenderPasses/Voxelization/Shading.slang`

这个函数在当前 pass 中主要用于：

- 主视角命中后，用 `viewDir` 选主法线。
- 直接光 shadow ray 发射前，用 `lightDir` 选 `shadowNormal`。
- env / ambient 方向评估时，也按对应方向选法线。

因此：

- `CheckCoverage` 更偏向“view direction 下的可见覆盖”。
- `CheckVisibility` 更偏向“light direction 下的内部透过/遮挡”。

## 最简总结

- `CheckEllipsoid`
  - 改几何命中边界。
  - 打开后用拟合椭球细化 voxel hit。
  - 对应的是 `rayMarching()` / `checkPrimitive()` / `Ellipsoid::clip()`。
- `CheckCoverage`
  - 改观察方向上的覆盖率 `C(v)`。
  - 公式是 `A_polygons(v) / A_primitive(v)`。
  - 作用在 `coverage * surface.eval(...)`。
- `CheckVisibility`
  - 改入射方向上的内部可见性 `V_internal(l)`。
  - 公式是 `A_polygons(l) / A_total(l)`。
  - 作用在 `calcInternalVisibility(l)`。
- 场景阴影另算。
  - `calcLightVisibility()` 是 shadow ray 遮挡，不属于 `CheckVisibility`。
