#include "VoxelizationShared.slang"
#include "Voxel/VoxelGrid.slang"
#include "Math/Polygon.slang"

RWStructuredBuffer<VoxelData> gBuffer;
StructuredBuffer<PolygonInVoxel> polygonBuffer;

cbuffer CB
{
    uint voxelCount;
    uint sampleFrequency;
    uint gBufferOffset;
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

        float totalProjArea = p.calcTotalProjArea(direction);
        polygonFunc.accumulate(totalProjArea, direction);
        polygonFunc.accumulate(totalProjArea, -direction);
        totalFunc.accumulate(totalProjArea, direction);
        totalFunc.accumulate(totalProjArea, -direction);
    }

    float weight = 4.f * PI / (times * 2);
    primitiveFunc.mul(2.35619449f * weight);
    polygonFunc.mul(weight);
    totalFunc.mul(weight);
}

void calc(uint offset)
{
    if (offset >= voxelCount)
        return;

    UniformSampleGenerator sg = UniformSampleGenerator(uint2(offset, 0), 0);
    Estimate(
        gBuffer[offset + gBufferOffset].ellipsoid,
        polygonBuffer[offset],
        sampleFrequency * sampleFrequency,
        sg,
        gBuffer[offset + gBufferOffset].polygonsProjAreaFunc,
        gBuffer[offset + gBufferOffset].primitiveProjAreaFunc,
        gBuffer[offset + gBufferOffset].totalProjAreaFunc,
    );
}

[numthreads(256, 1, 1)]
void main(uint3 offset: SV_DispatchThreadID)
{
    calc(offset.x);
}
