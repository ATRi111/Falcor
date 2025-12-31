#include "Math/Polygon.slang"
#include "Voxel/VoxelGrid.slang"
#include "VoxelizationShared.slang"

StructuredBuffer<Polygon> polygonBuffer;    //局部缓冲区
StructuredBuffer<PolygonRange> polygonRangeBuffer;
RWStructuredBuffer<VoxelData> gBuffer; 
RWStructuredBuffer<uint> blockMap; // 逻辑上是Texture2D<uint4>

cbuffer CB
{
    uint voxelCount;
    uint sampleFrequency;
    uint gBufferOffset;
    uint2 blockCount;
}

void Estimate(Ellipsoid e, PolygonRange range,inout UniformSampleGenerator sg, inout SphericalFunc polygonFunc, inout SphericalFunc primitiveFunc, inout SphericalFunc totalFunc)
{
    float3 cellMin = range.cellInt;
    float3 cellCenter = cellMin + 0.5f;
    for (uint i = 0; i < sampleFrequency; i++)
    {
        float3 direction = sample_sphere(Next2(sg));
        Basis2 basis = orthonormal_basis(direction);
        uint hitCount = 0;
        for (uint j = 0; j < sampleFrequency; j++)
        {
            SamplingRay ray = rayToVoxel(Next2(sg), direction, basis, cellCenter);
            float3 from = ray.origin;
            float3 to = from + 2 * ray.direction;
            float2 inOut = clip(cellMin, cellMin + 1.f, from, to);
            if (inOut.x >= 0) // 命中体素
            {
                float3 v = to - from;
                to = from + inOut.y * v - cellMin;
                from = from + inOut.x * v - cellMin;
                inOut = e.clip(from, to);
                if (inOut.x >= 0) // 命中图元
                    hitCount++;
            }
        }

        primitiveFunc.accumulate(hitCount, direction);
        primitiveFunc.accumulate(hitCount,-direction); // 正反方向的采样结果总是相同

        float totalProjArea = range.calcTotalProjArea(polygonBuffer, direction);
        polygonFunc.accumulate(totalProjArea, direction);
        polygonFunc.accumulate(totalProjArea, -direction);
        totalFunc.accumulate(totalProjArea, direction);
        totalFunc.accumulate(totalProjArea, -direction);
    }
    float weight = 4.f * PI / (sampleFrequency * 2);
    primitiveFunc.mul(PROJECT_CIRCLE_AREA * weight / sampleFrequency);
    polygonFunc.mul(weight);
    totalFunc.mul(weight);
}

void updateBlockMap(int3 cellInt)
{
    int3 blockInt = cellInt / BLOCK_TO_VOXEL;
    int component = blockInt.z / 32;
    uint value = 1 << blockInt.z % 32;
    uint index = blockInt.x + blockInt.y * blockCount.x;
    index = 4 * index + component; // 4个分量一组
    InterlockedOr(blockMap[index], value);
}

void calc(uint offset)
{
    if (offset >= voxelCount)
        return;

    uint index = offset + gBufferOffset;
    VoxelData data = gBuffer[index];
    if (!data.IsSolid())
        return;

    PolygonRange range = polygonRangeBuffer[index];

    data.ellipsoid.fit(polygonBuffer, range);
    data.ABSDF.normalizeSelf();

    SphericalFunc polyF = data.polygonsProjAreaFunc;
    SphericalFunc primF = data.primitiveProjAreaFunc;
    SphericalFunc totalF = data.totalProjAreaFunc;

    UniformSampleGenerator sg = UniformSampleGenerator(uint2(index, 0), 0);
    Estimate(data.ellipsoid, range, sg, polyF, primF, totalF);

    data.polygonsProjAreaFunc = polyF;
    data.primitiveProjAreaFunc = primF;
    data.totalProjAreaFunc = totalF;

    gBuffer[index] = data;

    updateBlockMap(range.cellInt);
}

[numthreads(256, 1, 1)]
void main(uint3 offset: SV_DispatchThreadID)
{
    calc(offset.x);
}
