RWTexture3D<uint> gOM;
RWTexture3D<uint> gMipOM;

cbuffer GridData
{
    uint3 voxelCount;
    uint3 voxelPerBit;
};

uint3 cellToMipCell(uint3 cell)
{
    return cell / voxelPerBit / uint3(4, 2, 4);
}

uint cellToBit(uint3 cell)
{
    uint3 temp = cell / voxelPerBit;
    uint x = temp.x % 4;
    uint y = temp.y % 2;
    uint z = temp.z % 4;
    uint index = x + (y << 2) + (z << 3);
    return 1u << index;
}

uint accumulateBit(uint3 cellMin)
{
    for (int x = 0; x < voxelPerBit.x; x++)
    {
        for (int y = 0; y < voxelPerBit.y; y++)
        {
            for (int z = 0; z < voxelPerBit.z; z++)
            {
                uint3 cell = cellMin + uint3(x, y, z);
                if (gOM[cell] != 0)
                    return cellToBit(cell);
            }
        }
    }
    return 0;
}

[numthreads(4, 8, 4)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint3 cellMin = dispatchThreadId * voxelPerBit; // 每次计算MipOM中一个体素的1bit，对应到OM中的4^3个体素
    uint bit = accumulateBit(cellMin);
    if (bit != 0)
    {
        uint3 mipCell = cellToMipCell(cellMin);
        InterlockedOr(gMipOM[mipCell], bit);
    }
}
