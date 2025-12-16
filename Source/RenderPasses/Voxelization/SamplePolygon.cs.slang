#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/Polygon.slang"

RWStructuredBuffer<VoxelData> gBuffer;
StructuredBuffer<PolygonInVoxel> polygonBuffer;

cbuffer CB
{
    uint solidVoxelCount;
    uint sampleFrequency;
    uint completeTimes;
    uint repeatTimes;
}

void Estimate(
    Ellipsoid e,
    PolygonInVoxel p,
    uint times,
    inout UniformSampleGenerator sg,
    inout SphericalFunc polygonFunc,
    inout SphericalFunc primitiveFunc,
    inout SphericalFunc totalFunc
)
{
    float3 cellCenter = p.cellMin + 0.5f;
    for (uint i = 0; i < times; i++)
    {
        float3 direction = sample_sphere(Next2(sg));
        Basis2 basis = orthonormal_basis(direction);
        SamplingRay ray = rayToVoxel(Next2(sg), direction, basis, cellCenter);

        float3 from = ray.origin;
        float3 to = from + 2 * ray.direction;
        float2 inOut = clip(p.cellMin, p.cellMin + 1.f, from, to);
        if (inOut.x >= 0) // 命中体素
        {
            float3 v = to - from;
            to = from + inOut.y * v - p.cellMin;
            from = from + inOut.x * v - p.cellMin;
            inOut = e.clip(from, to);
            if (inOut.x >= 0) // 命中图元
            {
                primitiveFunc.accumulate(direction);
                primitiveFunc.accumulate(-direction); // 正反方向的采样结果总是相同
            }
        }

        // 简单地认为图元总是包裹所有多边形
        uint hitCount = p.intersectRay(ray.origin, ray.direction);
        if (hitCount >= 1)
        {
            polygonFunc.accumulate(direction);
            polygonFunc.accumulate(-direction);
            totalFunc.accumulate(hitCount, direction);
            totalFunc.accumulate(hitCount, direction);
        }
    }
    if (completeTimes == repeatTimes - 1)
    {
        uint totalTimes = times * 2 * repeatTimes;
        float weight = 2.35619449f * 4.f * PI / totalTimes;
        polygonFunc.mul(weight);
        primitiveFunc.mul(weight);
        totalFunc.mul(weight);
    }
}

void calc(uint offset)
{
    UniformSampleGenerator sg = UniformSampleGenerator(uint2(offset, 0), completeTimes);
    if (offset >= solidVoxelCount)
        return;

    Estimate(
        gBuffer[offset].ellipsoid,
        polygonBuffer[offset],
        sampleFrequency * sampleFrequency,
        sg,
        gBuffer[offset].polygonsProjAreaFunc,
        gBuffer[offset].primitiveProjAreaFunc,
        gBuffer[offset].totalProjAreaFunc,
    );
}

[numthreads(256, 1, 1)]
void main(uint3 offset: SV_DispatchThreadID)
{
    calc(offset.x);
}
