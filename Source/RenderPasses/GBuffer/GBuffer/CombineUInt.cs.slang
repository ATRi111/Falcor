RWTexture3D<uint> gOccupancyMapLower;
RWTexture3D<uint> gOccupancyMapHigher;
RWTexture3D<uint2> gOccupancyMap;

[numthreads(4, 4, 4)]
void main(uint3 dispatchThreadId: SV_DispatchThreadID)
{
    uint lower = gOccupancyMapLower[dispatchThreadId];
    uint higher = gOccupancyMapHigher[dispatchThreadId];
    gOccupancyMap[dispatchThreadId] = uint2(lower, higher);
}
