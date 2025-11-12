// Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
#pragma once

#include "SpatialHashGridMacros.slangh"
#include "Utils/Math/MathConstants.slangh"

import SpatialHashGridParams;
import SpatialHashGridBufferUtils;
import NvHlslExtInclude;
import Utils.Debug.PixelDebug;
import Utils.Math.MathHelpers;

#define CACHED_PT_NORMAL_BUCKET_SIZE 4

typedef uint CacheInfo;
typedef uint2 HashKey; // 64 bit hash key

// CacheInfo getCurrentCacheInfoFromQueryPointMatID(const float3 queryPos, const float3 queryN, const float3 queryFaceN, const float3
// sceneBBoxMin, const float3 sceneBBoxMax, const float3 camPos, const uint materialID)
// {
//     HistogramSpatialHashGrid spatialHashGrid;
//     half jitter[6]; jitter[0] = jitter[1] = jitter[2] = jitter[3] = jitter[4] = jitter[5] = 0.f;
//     CacheInfo currentCacheInfoRayGuide =
//     createSpatialHashVoxel(spatialHashGrid, jitter, queryPos, queryN,
//         sceneBBoxMin, sceneBBoxMax, 0.f, length(queryPos - camPos), queryFaceN);
//     // CacheInfo currentCacheInfoRayGuide =
//     // createSpatialHashVoxelMatID(spatialHashGrid, jitter, queryPos, queryN,
//         // sceneBBoxMin, sceneBBoxMax, 0.f, length(queryPos - camPos), queryFaceN, materialID);
//     return currentCacheInfoRayGuide;
// }

CacheInfo getCurrentCacheInfoFromQueryPointMatID(
    const float3 queryPos,
    const float3 queryN,
    const float3 queryFaceN,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float3 camPos,
    const uint materialID
)
{
    HistogramSpatialHashGrid spatialHashGrid;
    half jitter[6];
    jitter[0] = jitter[1] = jitter[2] = jitter[3] = jitter[4] = jitter[5] = 0.f;
    CacheInfo currentCacheInfoRayGuide = createSpatialHashVoxelMatID(
        spatialHashGrid, jitter, queryPos, queryN, sceneBBoxMin, sceneBBoxMax, 0.f, length(queryPos - camPos), queryFaceN, materialID
    );
    return currentCacheInfoRayGuide;
}

CacheInfo getCurrentCacheInfoFromQueryPoint(
    const float3 queryPos,
    const float3 queryN,
    const float3 queryFaceN,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float3 camPos
)
{
    HistogramSpatialHashGrid spatialHashGrid;
    half jitter[6];
    jitter[0] = jitter[1] = jitter[2] = jitter[3] = jitter[4] = jitter[5] = 0.f;
    CacheInfo currentCacheInfoRayGuide = createSpatialHashVoxel(
        spatialHashGrid, jitter, queryPos, queryN, sceneBBoxMin, sceneBBoxMax, 0.f, length(queryPos - camPos), queryFaceN
    );
    return currentCacheInfoRayGuide;
}

CacheInfo getCurrentCacheInfoFromQueryPointMovMF(
    const float3 queryPos,
    const float3 queryN,
    const float3 queryFaceN,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float3 camPos
)
{
    MoVMFSpatialHashGrid spatialHashGrid;
    half jitter[6];
    jitter[0] = jitter[1] = jitter[2] = jitter[3] = jitter[4] = jitter[5] = 0.f;
    CacheInfo currentCacheInfoRayGuide = createSpatialHashVoxel(
        spatialHashGrid, jitter, queryPos, queryN, sceneBBoxMin, sceneBBoxMax, 0.f, length(queryPos - camPos), queryFaceN
    );
    return currentCacheInfoRayGuide;
}

CacheInfo getCurrentCacheInfoFromQueryPointMovMFMatID(
    const float3 queryPos,
    const float3 queryN,
    const float3 queryFaceN,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float3 camPos,
    const uint materialID
)
{
    MoVMFSpatialHashGrid spatialHashGrid;
    half jitter[6];
    jitter[0] = jitter[1] = jitter[2] = jitter[3] = jitter[4] = jitter[5] = 0.f;
    CacheInfo currentCacheInfoRayGuide = createSpatialHashVoxelMatID(
        spatialHashGrid, jitter, queryPos, queryN, sceneBBoxMin, sceneBBoxMax, 0.f, length(queryPos - camPos), queryFaceN, materialID
    );
    return currentCacheInfoRayGuide;
}

/// Compute the solid angle pdf of the camera direction sampler
///
/// @param U World space vector representing the horizontal half side of the camera screen, i.e. the vector from clip
/// (0,0) to clip (1,0)
/// @param V World space vector representing the vertical half side of the camera screen, i.e. the vector from clip
/// (0,0) to clip (0,1)
/// @param W World space vector from the camera origin to the center of the camera screen, i.e. the clip vector (0,0)
/// @param lenW Length of the W vector
/// @param squarePixelFocalLength The square of the focal length for the pixel
/// @param dir The direction for which the probability should be computed.
/// @return Probability in solid angle measure
float computeCameraDirectionSamplePdf(
    const float3 U,
    const float3 V,
    const float3 W,
    const float lenW,
    const float squarePixelFocalLength,
    float3 dir
)
{
    const float t = dot(dir, W) / (lenW * lenW);
    if (t < 0.0f)
    {
        return 0.0f;
    }

    const float3 I = dir / t - W;
    const float Ix = dot(I, U) / lengthSqr(U);
    const float Iy = dot(I, V) / lengthSqr(V);

    if (Ix >= -1.0f && Ix <= 1.0f && Iy >= -1.0f && Iy <= 1.0f)
    {
        const float cosTheta = dot(normalize(dir), W) / lenW;
        return squarePixelFocalLength / (cosTheta * cosTheta * cosTheta);
    }

    return 0.0f;
}

// return the image plane distance needed to have screen with unit area
float computeSquarePixelFocalLength(float2 t)
{
    return (1.0 / 4.0) / (t.x * t.y);
}

// -----------------------------------------------------------------------------
// CacheInfo related accessors
// -----------------------------------------------------------------------------

bool isValidCacheInfo(CacheInfo c)
{
    return c != CACHED_PT_INVALID_HASH_ENTRY;
}

// Workaround implementation for 'NvInterlockedAddFp32', this might be slow.
// See https://nvbugswb.nvidia.com/NvBugs5/SWBug.aspx?bugid=2805633
//
// This can fail and the returned value might be unexpected!
float NvInterlockedAddFp32_Emulated(RWByteAddressBuffer uav, uint byteAddress, float valueToAdd)
{
    // Emulated by using 'uint InterlockedCompareExchange' and conversion to float.
    uint expectedValue = uav.Load(byteAddress);
    float writeVal = asfloat(expectedValue) + valueToAdd;
    uint org;

    uav.InterlockedCompareExchange(byteAddress, expectedValue, asuint(writeVal), org);

    uint i = 256;
    [allow_uav_condition]
    while (i != 0)
    {
        expectedValue = org;
        writeVal = asfloat(org) + valueToAdd;
        uav.InterlockedCompareExchange(byteAddress, expectedValue, asuint(writeVal), org);

        if (org == expectedValue)
        {
            // Success.
            break;
        }
        --i;
    }

    return asfloat(org);
}

// -----------------------------------------------------------------------------
// Hashmap related code
// -----------------------------------------------------------------------------

interface ISpatialHashGrid
{
    // Increment hash counter single entry buffer
    void incrementHashCounter();
    // Num entries in a cache not counting elements per entry
    uint getNumEntries();
    // Returns stride element number allocated per entry in the hashgrid
    uint getStrideElementsPerEntry();
    // If compareKey == (value at baseAddress), swaps with key with compareKey
    // and returns (value at baseAddress) in oldValue
    void compareExchangeHashKeys64(uint baseAddr, uint2 compareKey, uint2 key, inout uint2 oldValue);
    // Writes timestamp into timestamp structured buffer at cacheInfo offset
    void updateTimestamp(uint cacheInfo, uint timestamp);

    void overrideEntry(const uint baseAddr, const HashKey key);

    void flagOverride(uint cacheInfo);

    void unflagOverride(uint cacheInfo);

    // Adds value.xyz to entry.xyz in flaot4 buffer at baseAddr and increments entry.w counter
    void addValueAndIncrementCounterFloat4(uint baseAddr, float4 value);
    // Adds value.x to entry.x in float2 buffer at baseAddr and increments entry.y counter
    void addValueAndIncrementCounterFloat2(uint baseAddr, float2 value);
    void addValueAndIncrementCounterFloat(uint baseAddr, float value);

    // Returns float4 value at baseAddr
    float4 readCacheValueFloat4(uint baseAddr);
    // Returns float2 value at baseAddr
    float2 readCacheValueFloat2(uint baseAddr);
    // Returns float value at baseAddr
    float readNewCacheValueFloat(uint baseAddr, uint elementOffset);
    //
    void setNewCacheElementFloat(uint baseAddr, uint elementOffset, float value);

    // Returns voxel size for the hashgrid
    uint getVoxelSize();
    // Return true if we assume "no conflicts" (aka we dont handle them and use the same data store in case of conflict)
    bool assumeNoConflicts();

    // Return true if distance based (iray) spatial hash func should be used, false otherwise
    bool useDistanceBasedHash();

    // In case useDistanceBasedHash()==true, this returns the distance based spatial hash func params
    void getDistanceBasedHashParams(out uint p0, out uint p1);

    // In case useDistanceBasedHash()==true, this will override the distance that the renderer use, to limit the min size of the voxels
    float getDistanceOverride();
};

// currently use for both rayguide and radiacne cache
struct HistogramSpatialHashGrid : ISpatialHashGrid
{
    void incrementHashCounter()
    {
        uint oldValue;
        gSpatialHashGridParams.RWHashTableCounter.InterlockedAdd(0, 1, oldValue);
    }

    uint getNumEntries() { return gSpatialHashGridParams.numEntries; }

    uint getStrideElementsPerEntry() { return gSpatialHashGridParams.strideElementsPerEntry; }

    void compareExchangeHashKeys64(uint baseAddr, uint2 invalidKey, uint2 key, inout uint2 oldValue)
    {
        const uint2 currentHashValue =
            uint2(gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 0), gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 4));
        // print("currentHashValue", currentHashValue);
        // print("baseAddr", baseAddr);

        if (all(currentHashValue == key))
        {
            oldValue = key;
        }
        else
        {
            // print("invalidKey", invalidKey);
            uint64_t prevKey = 0;
            RtxInterlockedCompareExchangeU64(
                gSpatialHashGridParams.RWHashMapKey, baseAddr, Uint2ToUint64(invalidKey), Uint2ToUint64(key), prevKey
            );
            oldValue = Uint64ToUint2(prevKey);
            // print("key", key);
            // print("oldValue", oldValue);
        }
        // uint2 currentHashValue2 = uint2(gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 0),
        // gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 4));
        // //print("currentHashValue2", currentHashValue2);
    }

    void updateTimestamp(uint cacheInfo, uint timestamp) { gSpatialHashGridParams.RWTimeStamps[cacheInfo] = timestamp; }

    void overrideEntry(const uint baseAddr, const HashKey key)
    {
        gSpatialHashGridParams.RWHashMapKey.Store(baseAddr + 0, key.x);
        gSpatialHashGridParams.RWHashMapKey.Store(baseAddr + 4, key.y);
    }

    void flagOverride(uint cacheInfo) { gSpatialHashGridParams.RWOverrideFlags[cacheInfo] = 1; }

    void unflagOverride(uint cacheInfo) { gSpatialHashGridParams.RWOverrideFlags[cacheInfo] = 0; }

    void addValueAndIncrementCounterFloat4(uint baseAddr, float4 value)
    {
        // Not implemented for Light Cache Grid
    }

    void addValueAndIncrementCounterFloat2(uint baseAddr, float2 value)
    {
        if (value.x != 0.f)
        {
            RtxInterlockedAddF32(gSpatialHashGridParams.RWNewCacheValues, baseAddr + 0 * 4, value.x);
        }
        RtxInterlockedAddF32(gSpatialHashGridParams.RWNewCacheValues, baseAddr + 1 * 4, 1.0f); // this is the sample counter
    }

    void addValueAndIncrementCounterFloat(uint baseAddr, float value) {}

    float4 readCacheValueFloat4(uint baseAddr)
    {
        // Not implemented for Light Cache Grid
        return 0;
    }

    float2 readCacheValueFloat2(uint baseAddr) { return getCacheEntryFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr); }

    float readNewCacheValueFloat(uint baseAddr, uint elementOffset)
    {
        return getCacheEntryElementFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, elementOffset);
    }

    void setNewCacheElementFloat(uint baseAddr, uint elementOffset, float value)
    {
        setCacheElementFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, elementOffset, value);
    }

    uint getVoxelSize() { return gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eVoxelSize]; }

    bool assumeNoConflicts() { return (gSpatialHashGridParams.flags & SPATIAL_HASH_GRID_eSpatialHashGridDontResolveConflicts) != 0; }

    bool useDistanceBasedHash() { return (gSpatialHashGridParams.flags & SPATIAL_HASH_GRID_eSpatialHashGridDistanceBasedSpatialHash) != 0; }

    void getDistanceBasedHashParams(out uint p0, out uint p1)
    {
        p0 = gSpatialHashGridParams.distanceBasedHashP0;
        p1 = gSpatialHashGridParams.distanceBasedHashP1;
    }

    float getDistanceOverride() { return gSpatialHashGridParams.distanceOverride; }
};

struct MoVMFSpatialHashGrid : ISpatialHashGrid
{
    void incrementHashCounter()
    {
        uint oldValue;
        gSpatialHashGridParams.RWHashTableCounter.InterlockedAdd(0, 1, oldValue);
    }

    uint getNumEntries() { return gSpatialHashGridParams.numEntries; }

    uint getStrideElementsPerEntry() { return gSpatialHashGridParams.strideElementsPerEntry; }

    void compareExchangeHashKeys64(uint baseAddr, uint2 invalidKey, uint2 key, inout uint2 oldValue)
    {
        const uint2 currentHashValue =
            uint2(gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 0), gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 4));
        // print("currentHashValue", currentHashValue);
        // print("baseAddr", baseAddr);

        if (all(currentHashValue == key))
        {
            oldValue = key;
        }
        else
        {
            // print("invalidKey", invalidKey);
            uint64_t prevKey = 0;
            RtxInterlockedCompareExchangeU64(
                gSpatialHashGridParams.RWHashMapKey, baseAddr, Uint2ToUint64(invalidKey), Uint2ToUint64(key), prevKey
            );
            oldValue = Uint64ToUint2(prevKey);
            // print("key", key);
            // print("oldValue", oldValue);
        }
        // uint2 currentHashValue2 = uint2(gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 0),
        // gSpatialHashGridParams.RWHashMapKey.Load(baseAddr + 4));
        // //print("currentHashValue2", currentHashValue2);
    }

    void updateTimestamp(uint cacheInfo, uint timestamp) { gSpatialHashGridParams.RWTimeStamps[cacheInfo] = timestamp; }

    void overrideEntry(const uint baseAddr, const HashKey key)
    {
        gSpatialHashGridParams.RWHashMapKey.Store(baseAddr + 0, key.x);
        gSpatialHashGridParams.RWHashMapKey.Store(baseAddr + 4, key.y);
    }

    void flagOverride(uint cacheInfo) { gSpatialHashGridParams.RWOverrideFlags[cacheInfo] = 1; }

    void unflagOverride(uint cacheInfo) { gSpatialHashGridParams.RWOverrideFlags[cacheInfo] = 0; }

    void addValueAndIncrementCounterFloat4(uint baseAddr, float4 value) {}

    void addValueAndIncrementCounterFloat2(uint baseAddr, float2 value)
    {
        if (value.x != 0.f)
        {
            RtxInterlockedAddF32(gSpatialHashGridParams.RWNewCacheValues, baseAddr + 0 * 4, value.x);
        }
        RtxInterlockedAddF32(gSpatialHashGridParams.RWNewCacheValues, baseAddr + 1 * 4, 1.0f); // this is the sample counter
    }

    void addValueAndIncrementCounterFloat(uint baseAddr, float value)
    {
        RtxInterlockedAddF32(gSpatialHashGridParams.RWNewCacheValues, baseAddr, value);
    }

    float4 readCacheValueFloat4(uint baseAddr)
    {
        // Not implemented for Light Cache Grid
        return 0;
    }

    float2 readCacheValueFloat2(uint baseAddr) { return getCacheEntryFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr); }

    float readNewCacheValueFloat(uint baseAddr, uint elementOffset)
    {
        return getCacheEntryElementFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, elementOffset);
    }

    void setNewCacheElementFloat(uint baseAddr, uint elementOffset, float value)
    {
        setCacheElementFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, elementOffset, value);
    }

    uint getVoxelSize() { return gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eVoxelSize]; }

    bool assumeNoConflicts() { return (gSpatialHashGridParams.flags & SPATIAL_HASH_GRID_eSpatialHashGridDontResolveConflicts) != 0; }

    bool useDistanceBasedHash() { return (gSpatialHashGridParams.flags & SPATIAL_HASH_GRID_eSpatialHashGridDistanceBasedSpatialHash) != 0; }

    void getDistanceBasedHashParams(out uint p0, out uint p1)
    {
        p0 = gSpatialHashGridParams.distanceBasedHashP0;
        p1 = gSpatialHashGridParams.distanceBasedHashP1;
    }

    float getDistanceOverride() { return gSpatialHashGridParams.distanceOverride; }
};

void finishHashMapWrite<SpatialHashGrid : ISpatialHashGrid>(SpatialHashGrid spatialHashGrid)
{
    spatialHashGrid.incrementHashCounter();
}

// For inserting a key into a hashmap.
// @return True if successful
bool insertIntoHashMap<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    const HashKey key,
    const uint hashCode,
    out uint cacheSlot
)
{
    // @todo: verify this
    const uint tableSize = spatialHashGrid.getNumEntries();
    const uint skipIndex = (hashCode / tableSize) | 1;
    // print("hashCode", hashCode);
    // print("tableSize", tableSize);
    // print("skipIndex", skipIndex);

    uint slot = hashCode & (tableSize - 1);
    // print("slot", slot);

    const uint invalidKey = CACHED_PT_INVALID_HASH_ENTRY;
    uint2 oldValue = uint2(invalidKey, invalidKey);

    // loop through the entire hash-table exactly once
    uint initSlot = slot;

    // In the orig paper, we loop forever. GTC China 2019 scene seem to hang (fulls the hash map?) if we dont have a
    // safe stop
    uint counter = 0;

    bool isNew = false;

    const bool assumeNoConflicts = spatialHashGrid.assumeNoConflicts();
    // https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/interlockedcompareexchange
    // Spec: "If you call InterlockedCompareExchange in a for or while compute shader loop, to properly compile,
    // you must use the [allow_uav_condition] attribute on that loop."

    // daqi: why use buckets?

    const uint MAX_ITERS = 16;
    [allow_uav_condition]
    while (counter++ < MAX_ITERS)
    {
        // Find the bucket containing this slot.
        const uint currentBucket = (slot / CACHED_PT_NORMAL_BUCKET_SIZE) * CACHED_PT_NORMAL_BUCKET_SIZE;
        // Search within the bucket.
        [allow_uav_condition] // @todo: unroll?
        for (uint bucketIndex = 0; bucketIndex < CACHED_PT_NORMAL_BUCKET_SIZE; ++bucketIndex)
        {
            //
            // Using 2x32 bit atomics.
            // RWHashMapKey is RGRWStructuredBuffer<uint>.
            //
            const uint baseAddr = (currentBucket + bucketIndex) * 8;
            spatialHashGrid.compareExchangeHashKeys64(baseAddr, invalidKey, key, oldValue);

            if (all(oldValue == uint2(CACHED_PT_INVALID_HASH_ENTRY, CACHED_PT_INVALID_HASH_ENTRY)))
            {
                isNew = true;
                slot = currentBucket + bucketIndex;
                break;
            }

            const bool isLastIter = (counter == (MAX_ITERS - 1) && (bucketIndex == CACHED_PT_NORMAL_BUCKET_SIZE - 1));
            if (assumeNoConflicts || all(oldValue == key) || isLastIter) // if last iter, need to clean original data
            {
                if (isLastIter && !all(oldValue == key))
                {
                    // directly override the hashkey
                    spatialHashGrid.overrideEntry(baseAddr, key);
                    spatialHashGrid.flagOverride(currentBucket + bucketIndex);
                }

                oldValue = key;
                slot = currentBucket + bucketIndex;
                break;
            }
        }

        // breaking out of the while loop in case of a successful compare-and-swap.
        if (all(oldValue == uint2(CACHED_PT_INVALID_HASH_ENTRY, CACHED_PT_INVALID_HASH_ENTRY)) || all(oldValue == key))
        {
            break;
        }

        // linear probing
        slot = (slot + skipIndex) & (tableSize - 1u);

        // break if we looped! (this rarely happens due to the randomneed of skipIndex)
        if (slot == initSlot)
        {
            cacheSlot = invalidKey;
            return false;
        }
    }

    if (isNew)
    {
        finishHashMapWrite(spatialHashGrid);
    }
    cacheSlot = slot;
    return true;
}

float3 clampSample(float3 v)
{
    // @todo: firefly filtering?
    // @todo: clamp to 0.0 at least
    // return is_finite(v) ? min(v, firefly_filter) : cugar::Vector3f(0.0f);
    // return v;
    return max(float3(0, 0, 0), v);
}

// 32 bit Jenkin's hash, documented here http://burtleburtle.net/bob/hash/integer.html
uint hashJenkins(uint a)
{
    // http://burtleburtle.net/bob/hash/integer.html
    a = (a + 0x7ed55d16) + (a << 12);
    a = (a ^ 0xc761c23c) ^ (a >> 19);
    a = (a + 0x165667b1) + (a << 5);
    a = (a + 0xd3a2646c) ^ (a << 9);
    a = (a + 0xfd7046c5) + (a << 3);
    a = (a ^ 0xb55a4f09) ^ (a >> 16);
    return a;
}

uint hash(uint2 k)
{
    return hashJenkins(k.x) ^ hashJenkins(k.y);
}

float lengthSqr(float3 v)
{
    return dot(v, v);
}

bool isNanOrInf(float f)
{
    return isnan(f) || isinf(f);
}

float roundFloat(float x)
{
    const int y = x > 0.0f ? int(x) : int(x) - 1;
    return (x - float(y) > 0.5f) ? float(y) + 1.0f : float(y);
}

float fmodf(const float a, const float b)
{
    return a - b * floor(a / b);
}

float modFloat(const float x, const float m)
{
    // @todo: double check this
#if 1
    return x > 0.0f ? fmodf(x, m) : m - fmodf(-x, m);
#else
    return fmod(x, m);
#endif
}

float max3(float3 v)
{
    return max(v.x, max(v.y, v.z));
}

float3 cacheInfoToColor(CacheInfo c)
{
    float3 col = 0;
    // Using 8 bits for rgb. xor-ing with the alpha bits.
    col.x = float(((c >> 24) & 0xFF) ^ (c & 0xFF)) / 255.f;
    col.y = float(((c >> 16) & 0xFF) ^ (c & 0xFF)) / 255.f;
    col.z = float(((c >> 8) & 0xFF) ^ (c & 0xFF)) / 255.f;
    return col;
}

/**
 * Maps a vector from a sphere (e.g. normal) to a uniform square distribution.
 */
float2 uniformSphereToSquare(float3 vec)
{
    const float cosTheta = vec.z;
    float phi;
    if (abs(vec.z) >= 1.0f - 1.0e-5f)
    {
        phi = 0.0f;
    }
    else
    {
        phi = atan2(vec.y, vec.x);
        phi = phi < 0.0f ? phi + 2.0f * M_PI : phi;
    }
    return float2(phi / (2.0f * M_PI), (cosTheta + 1.0f) * 0.5f);
}

// octahedron map?

float2 sphereToSquareOctahedron(float3 dir)
{
    const float2 octCoords = ndir_to_oct_snorm(dir);
    const float2 squareCoords = (octCoords + 1) * 0.5f;
    return squareCoords;
}

// For packing a float2 into numBits of a uint
uint packVector(float2 v, uint numBits)
{
    const uint maxValue = (1u << numBits) - 1u;
    const uint x = uint(v.x * float(maxValue));
    const uint y = uint(v.y * float(maxValue));
    return x | (y << numBits);
}

float myLogf(float x, float basis)
{
    //          log_d(x)
    // log_b = ---------
    //          log_d(b)
    return log(x) / log(basis);
}

#if 0
/**
 * Original hash function from iray experiments from Johannes Jendersie:
 * https://confluence.nvidia.com/display/~jjendersie/Spatial+Cache+Placement
 *
 * Note: This version does not incorporate the normal.
 */
int4 calc_log_grid_pos(float3 samplePos, float distance, uint p0, uint p1, const float3 triangleNormal, const half samples[6])
{
    const float sh_epsilon = 0.001f;
    const float sh_basis = 2.f;
    const float LOD_MULTIPLIER = 8.f;
    const int grid_level = floor(myLogf(max(sh_epsilon, distance), sh_basis));
    const float voxel_size = pow(sh_basis, grid_level);
    const int3 grid_pos = floor(samplePos / voxel_size * LOD_MULTIPLIER);
    return int4(grid_pos.xyz, grid_level);
}
#else
int4 calc_log_grid_pos(float3 samplePos, float distance /*Euclidean*/, uint p0, uint p1, const float3 triangleNormal, const half samples[6])
{
    const float sh_epsilon = 0.001f;
    const float sh_basis = p1 * 0.1; // basically the number of steps that we want as LoD.
    float lodMultiplier = p0 * 0.1;  // Smaller means larger cell, basically cell-size

    int gridLevel = floor(myLogf(max(sh_epsilon, distance), sh_basis));

    const float PROB_FOR_GRID_JITTER = 0.05;
    const float pJitter = samples[5];
    float3 rndDir = float3(0.f, 0.f, 0.f);

    const bool lodJitterEnabled = (pJitter != 0.f);
    if (lodJitterEnabled)
    {
        if (pJitter < PROB_FOR_GRID_JITTER)
        {
            gridLevel--;
        }
        else if (pJitter > (1.f - PROB_FOR_GRID_JITTER))
        {
            gridLevel++;
        }
    }

    // lodMultiplier *= gridLevel;
    ////print("gridLevel", gridLevel);
    const float voxelSize = pow(sh_basis, gridLevel);
    const float2 rndSample = float2(samples[0], samples[1]);

    const bool positionJitterEnabled = (rndSample.x != 0);
    if (positionJitterEnabled)
    {
        float3 b0 = 0;
        float3 b1 = 0;
        branchlessONB(triangleNormal, b0, b1);
        const float C = voxelSize / lodMultiplier; // pos jitter size is 1 voxel size
        rndDir = b0 * (-0.5f + rndSample.x) * C + b1 * (-0.5f + rndSample.y) * C;
    }

    if (lengthSqr(triangleNormal) > 0.f)
    {
        samplePos += rndDir;
    }

    const int3 gridPos = floor(samplePos / voxelSize * lodMultiplier);
    return int4(gridPos.xyz, gridLevel);
}
#endif

// From Iray experiments
// https://confluence.nvidia.com/display/~jjendersie/Spatial+Cache+Placement
HashKey computeSpatialHashDistance(
    float3 P,
    float3 shadingNormal,
    float3 bboxMin,
    float3 bboxMax,
    half samples[6],
    float distance,
    uint p0,
    uint p1,
    float3 triangleNormal
)
{
    const int4 johHash = calc_log_grid_pos(P, distance, p0, p1, triangleNormal, samples);
    const uint uiLogGridSize = johHash.w;
    const uint3 uiShadingLoc = johHash.xyz;
    ////print("johHash", johHash);

    const uint normalBits = 4;
    const float2 normalJitter = float2(0, 0); // for some reason rendering gets darker float2(samples[3], samples[4]) / float(1u <<
                                              // (normalBits / 2));
    float2 N_uv = uniformSphereToSquare(shadingNormal); // sphereToSquareOctahedron(shadingNormal);//
    N_uv.x = modFloat(N_uv.x + normalJitter.x, 1.0f);
    N_uv.y = min(N_uv.y + normalJitter.y, 1.0f);

    // if we don't use normal binning, use the extra bits for location hashing
    if (lengthSqr(shadingNormal) != 0.f)
    {
        const uint comp_mask = (1u << 17) - 1u; // => 0x1FFFF, 17 bits
        const uint shadingNormal8Bit = packVector(N_uv, normalBits);

        //
        // 64 bit shading key:
        // 17 bits x
        // 17 bits y
        // 17 bits z
        //  5 bits logGridSize                  // @todo: what's this?
        //  8 bits normal
        //
        // The original code was using 64 bit uints and the shading key looked likes this:
        // const uint64 shading_key = (uint64(uiShadingLoc.x & comp_mask) <<  0) | (uint64(uiShadingLoc.y & comp_mask) <<
        // 17) |
        //                            (uint64(uiShadingLoc.z & comp_mask) << 34) | (uint64(uiLogGridSize) << 51) |
        //                            (uint64(shadingNormal8Bit) << 56);
        //
        // We split the key into 2x32 bits which makes the above operation a bit cumbersome around uiShadingLoc.y:
        const uint uiShadingLocY2Bits = (uiShadingLoc.y & comp_mask) >> 15;
        const uint uiShadingLocY15Bits = (uiShadingLoc.y & 0x7FFF); // 7FFF = 15 bits

        const uint uiLogGridMask = (1 << 5) - 1; // 5 bits
        const uint shadingKey0 = (uiShadingLoc.x & comp_mask) | (uiShadingLocY15Bits << 17);
        const uint shadingKey1 = (uiShadingLocY2Bits) | ((uiShadingLoc.z & comp_mask) << 2) | ((uiLogGridSize & uiLogGridMask) << 19) |
                                 (shadingNormal8Bit << 24);

        return uint2(shadingKey0, shadingKey1);
    }
    else
    {
        // 64 bit shading key:
        // 19 bits x
        // 19 bits y
        // 19 bits z
        //  5 bits logGridSize
        //  0 bits normal
        const uint comp_mask = (1u << 19) - 1u;                     // => 0x7FFFF, 19 bits
        const uint uiShadingLocY13Bits = (uiShadingLoc.y & 0x1FFF); // 0x1FFF = 13 bits
        const uint shadingKey0 = (uiShadingLoc.x & comp_mask) | (uiShadingLocY13Bits << 19);

        const uint uiShadingLocY6Bits = (uiShadingLoc.y & comp_mask) >> 13;

        const uint uiLogGridMask = (1 << 5) - 1;                                // 5 bits
        const uint shadingKey1 = (uiShadingLocY6Bits) |                         // 6 bits
                                 ((uiShadingLoc.z & comp_mask) << 6) |          // 19 bits
                                 ((uiLogGridSize & uiLogGridMask) << (6 + 19)); // 5 bits
        ////print("shadingKey0", shadingKey0);

        ////print("shadingKey1", shadingKey1);

        return uint2(shadingKey0, shadingKey1);
    }
}

HashKey computeSpatialHashDistanceMatID(
    float3 P,
    float3 shadingNormal,
    float3 bboxMin,
    float3 bboxMax,
    half samples[6],
    float distance,
    uint p0,
    uint p1,
    float3 triangleNormal,
    uint materialID
)
{
    const int4 johHash = calc_log_grid_pos(P, distance, p0, p1, triangleNormal, samples);
    const uint uiLogGridSize = johHash.w;
    const uint3 uiShadingLoc = johHash.xyz;
    ////print("johHash", johHash);

    const uint normalBits = 4;
    const float2 normalJitter = float2(0, 0); // for some reason rendering gets darker float2(samples[3], samples[4]) / float(1u <<
                                              // (normalBits / 2));
    float2 N_uv = uniformSphereToSquare(shadingNormal); // sphereToSquareOctahedron(shadingNormal);//
    N_uv.x = modFloat(N_uv.x + normalJitter.x, 1.0f);
    N_uv.y = min(N_uv.y + normalJitter.y, 1.0f);

    // if we don't use normal binning, use the extra bits for location hashing
    if (lengthSqr(shadingNormal) != 0.f)
    {
        const uint coord_mask = (1u << 16) - 1u;   // => 0x1FFFF, 16 bits
        const uint uiLogGridMask = (1u << 3) - 1;  // 3 bits
        const uint materialIDMask = (1u << 5) - 1; // 5 bits
        // New layout:
        // shadingKey0: x[16] | y[16]
        // shadingKey1: z[16] | logGridSize[3] | normal[8] | materialID[5]
        const uint shadingNormal8Bit = packVector(N_uv, normalBits);

        const uint shadingKey0 = (uiShadingLoc.x & coord_mask) | ((uiShadingLoc.y & coord_mask) << 16);

        const uint shadingKey1 = (uiShadingLoc.z & coord_mask) | ((uiLogGridSize & uiLogGridMask) << 16) | (shadingNormal8Bit << 19) |
                                 ((materialID & materialIDMask) << 27);
        return uint2(shadingKey0, shadingKey1);
    }
    else
    {
        // 64 bit shading key:
        // 19 bits x
        // 19 bits y
        // 19 bits z
        //  5 bits logGridSize
        //  0 bits normal
        const uint comp_mask = (1u << 19) - 1u;                     // => 0x7FFFF, 19 bits
        const uint uiShadingLocY13Bits = (uiShadingLoc.y & 0x1FFF); // 0x1FFF = 13 bits
        const uint shadingKey0 = (uiShadingLoc.x & comp_mask) | (uiShadingLocY13Bits << 19);

        const uint uiShadingLocY6Bits = (uiShadingLoc.y & comp_mask) >> 13;

        const uint uiLogGridMask = (1 << 5) - 1;                                // 5 bits
        const uint shadingKey1 = (uiShadingLocY6Bits) |                         // 6 bits
                                 ((uiShadingLoc.z & comp_mask) << 6) |          // 19 bits
                                 ((uiLogGridSize & uiLogGridMask) << (6 + 19)); // 5 bits
        ////print("shadingKey0", shadingKey0);

        ////print("shadingKey1", shadingKey1);

        return uint2(shadingKey0, shadingKey1);
    }
}

/**
 * Compute a 64 bit hash value from a position + normal + coneRadius
 */
HashKey computeSpatialHashCone(
    float3 P,
    float3 shadingNormal,
    float3 bboxMin,
    float3 bboxMax,
    half samples[6],
    float coneRadius,
    float distance
)
{
    const uint normalBits = 4;
    const float3 worldDiagonal = bboxMax - bboxMin;
    const float worldExtent = max3(worldDiagonal);

    const float floatGridSize = max(worldExtent / (2.0 * coneRadius), 1.0);
    const float floatLogGridSize = log2(floatGridSize);
    const uint tempGridSize = uint(floatLogGridSize); // in [0,17] -> need 5 bits!
    const float rLogGridSize = floatLogGridSize - tempGridSize;
    const uint uiLogGridSize = tempGridSize + (samples[5] < rLogGridSize ? 1u : 0u);
    const uint uiGridSize = 1u << uiLogGridSize;
    const float3 vShadingLoc = float(uiGridSize) * (P - bboxMin) / worldExtent;
    const uint3 uiShadingLoc = uint3(
        uint(max(roundFloat(vShadingLoc.x + samples[0] - 0.5f), 0.0f)),
        uint(max(roundFloat(vShadingLoc.y + samples[1] - 0.5f), 0.0f)),
        uint(max(roundFloat(vShadingLoc.z + samples[2] - 0.5f), 0.0f))
    );
    const float2 normalJitter = float2(samples[3], samples[4]) / float(1u << (normalBits / 2));
    float2 N_uv = uniformSphereToSquare(shadingNormal);
    N_uv.x = modFloat(N_uv.x + normalJitter.x, 1.0f);
    N_uv.y = min(N_uv.y + normalJitter.y, 1.0f);
    const uint comp_mask = (1u << 17) - 1u; // => 0x1FFFF, 17 bits
    const uint shadingNormal8Bit = packVector(N_uv, normalBits / 2);

    //
    // 64 bit shading key:
    // 17 bits x
    // 17 bits y
    // 17 bits z
    //  5 bits logGridSize                  // @todo: what's this?
    //  8 bits normal
    //
    // The original code was using 64 bit uints and the shading key looked likes this:
    // const uint64 shading_key = (uint64(uiShadingLoc.x & comp_mask) <<  0) | (uint64(uiShadingLoc.y & comp_mask) <<
    // 17) |
    //                            (uint64(uiShadingLoc.z & comp_mask) << 34) | (uint64(uiLogGridSize) << 51) |
    //                            (uint64(shadingNormal8Bit) << 56);
    //
    // We split the key into 2x32 bits which makes the above operation a bit cumbersome around uiShadingLoc.y:
    const uint uiShadingLocY2Bits = (uiShadingLoc.y & comp_mask) >> 15;
    const uint uiShadingLocY15Bits = (uiShadingLoc.y & 0x7FFF); // 7FFF = 15 bits
    const uint shadingKey0 = (uiShadingLoc.x & comp_mask) | (uiShadingLocY15Bits << 17);
    const uint shadingKey1 = (uiShadingLocY2Bits) | ((uiShadingLoc.z & comp_mask) << 2) | (uiLogGridSize << 19) | (shadingNormal8Bit << 24);
    return uint2(shadingKey0, shadingKey1);
}

HashKey computeSpatialHashConeMatID(
    float3 P,
    float3 shadingNormal,
    float3 bboxMin,
    float3 bboxMax,
    half samples[6],
    float coneRadius,
    float distance,
    uint materialID
)
{
    const uint normalBits = 4;
    const float3 worldDiagonal = bboxMax - bboxMin;
    const float worldExtent = max3(worldDiagonal);

    const float floatGridSize = max(worldExtent / (2.0 * coneRadius), 1.0);
    const float floatLogGridSize = log2(floatGridSize);
    const uint tempGridSize = uint(floatLogGridSize); // in [0,17] -> need 5 bits!
    const float rLogGridSize = floatLogGridSize - tempGridSize;
    const uint uiLogGridSize = tempGridSize + (samples[5] < rLogGridSize ? 1u : 0u);
    const uint uiGridSize = 1u << uiLogGridSize;
    const float3 vShadingLoc = float(uiGridSize) * (P - bboxMin) / worldExtent;
    const uint3 uiShadingLoc = uint3(
        uint(max(roundFloat(vShadingLoc.x + samples[0] - 0.5f), 0.0f)),
        uint(max(roundFloat(vShadingLoc.y + samples[1] - 0.5f), 0.0f)),
        uint(max(roundFloat(vShadingLoc.z + samples[2] - 0.5f), 0.0f))
    );
    const float2 normalJitter = float2(samples[3], samples[4]) / float(1u << (normalBits / 2));
    float2 N_uv = uniformSphereToSquare(shadingNormal);
    N_uv.x = modFloat(N_uv.x + normalJitter.x, 1.0f);
    N_uv.y = min(N_uv.y + normalJitter.y, 1.0f);
    const uint comp_mask = (1u << 16) - 1u; // => 0x1FFFF, 16 bits
    const uint shadingNormal8Bit = packVector(N_uv, normalBits);

    //
    // 64 bit shading key:
    // 17 bits x
    // 17 bits y
    // 17 bits z
    //  5 bits logGridSize                  // @todo: what's this?
    //  8 bits normal
    //
    // The original code was using 64 bit uints and the shading key looked likes this:
    // const uint64 shading_key = (uint64(uiShadingLoc.x & comp_mask) <<  0) | (uint64(uiShadingLoc.y & comp_mask) <<
    // 17) |
    //                            (uint64(uiShadingLoc.z & comp_mask) << 34) | (uint64(uiLogGridSize) << 51) |
    //                            (uint64(shadingNormal8Bit) << 56);
    //
    // We split the key into 2x32 bits which makes the above operation a bit cumbersome around uiShadingLoc.y:
    const uint coord_mask = (1u << 16) - 1u;   // => 0x1FFFF, 16 bits
    const uint uiLogGridMask = (1u << 3) - 1;  // 3 bits
    const uint materialIDMask = (1u << 5) - 1; // 5 bits
    // New layout:
    // shadingKey0: x[16] | y[16]
    // shadingKey1: z[16] | logGridSize[3] | normal[8] | materialID[5]

    const uint shadingKey0 = (uiShadingLoc.x & coord_mask) | ((uiShadingLoc.y & coord_mask) << 16);

    const uint shadingKey1 = (uiShadingLoc.z & coord_mask) | ((uiLogGridSize & uiLogGridMask) << 16) | (shadingNormal8Bit << 19) |
                             ((materialID & materialIDMask) << 27);
    return uint2(shadingKey0, shadingKey1);
}

HashKey computeSpatialHash<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    float3 P,
    float3 shadingNormal,
    float3 bboxMin,
    float3 bboxMax,
    half samples[6],
    float coneRadius,
    float distance,
    float3 triangleNormal
)
{
    if (!spatialHashGrid.useDistanceBasedHash())
    {
        return computeSpatialHashCone(P, shadingNormal, bboxMin, bboxMax, samples, coneRadius, distance);
    }
    else
    {
        ////print("use Distance Based", 1);
        uint p0, p1;
        spatialHashGrid.getDistanceBasedHashParams(p0, p1);
        ////print("p0 p1", uint2(p0, p1));
        const float3 offset = float3(M_PI_2, M_PI_2, M_PI_2); // plane laying in 0 axis due to fp prec will be moired
                                                              // into 2 voxels, so offset the 0 (it is common case)
        return computeSpatialHashDistance(P + offset, shadingNormal, bboxMin, bboxMax, samples, distance, p0, p1, triangleNormal);
    }
}

HashKey computeSpatialHashMatID<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    float3 P,
    float3 shadingNormal,
    float3 bboxMin,
    float3 bboxMax,
    half samples[6],
    float coneRadius,
    float distance,
    float3 triangleNormal,
    uint materialID
)
{
    if (!spatialHashGrid.useDistanceBasedHash())
    {
        return computeSpatialHashConeMatID(P, shadingNormal, bboxMin, bboxMax, samples, coneRadius, distance, materialID);
    }
    else
    {
        ////print("use Distance Based", 1);
        uint p0, p1;
        spatialHashGrid.getDistanceBasedHashParams(p0, p1);
        ////print("p0 p1", uint2(p0, p1));
        const float3 offset = float3(M_PI_2, M_PI_2, M_PI_2); // plane laying in 0 axis due to fp prec will be moired
                                                              // into 2 voxels, so offset the 0 (it is common case)
        return computeSpatialHashDistanceMatID(
            P + offset, shadingNormal, bboxMin, bboxMax, samples, distance, p0, p1, triangleNormal, materialID
        );
    }
}

// not used
// void updateSpatialHashVoxel<SpatialHashGrid : ISpatialHashGrid>(SpatialHashGrid spatialHashGrid,
//                                                                 CacheInfo cacheInfo,
//                                                                 float4 valueToAdd,
//                                                                 uint frameNumber)
// {
//     if (spatialHashGrid.getNumEntries() == 0)
//     {
//         return;
//     }

//     if ((cacheInfo < spatialHashGrid.getNumEntries()) && isValidCacheInfo(cacheInfo))
//     {
//         spatialHashGrid.updateTimestamp(cacheInfo, frameNumber);
//         uint baseAddr = float4CacheAddress(cacheInfo);
//         spatialHashGrid.addValueAndIncrementCounterFloat4(baseAddr, (valueToAdd));
//     }
// }

void updateSpatialHashVoxelElement<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    CacheInfo cacheInfo,
    float valueToAdd,
    uint element,
    uint frameNumber
)
{
    if (spatialHashGrid.getNumEntries() == 0 || isNanOrInf(valueToAdd.x))
    {
        return;
    }

    if ((cacheInfo < spatialHashGrid.getNumEntries()) && isValidCacheInfo(cacheInfo))
    {
        const uint baseAddr = floatCacheEntryAddress(cacheInfo, spatialHashGrid.getStrideElementsPerEntry()) + floatCacheAddress(element);
        spatialHashGrid.addValueAndIncrementCounterFloat(baseAddr, valueToAdd);
        spatialHashGrid.updateTimestamp(cacheInfo, frameNumber);
    }
}

void updateSpatialHashVoxelElement2<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    CacheInfo cacheInfo,
    float2 valueToAdd,
    uint element,
    uint frameNumber
)
{
    if (spatialHashGrid.getNumEntries() == 0 || isNanOrInf(valueToAdd.x))
    {
        return;
    }

    if ((cacheInfo < spatialHashGrid.getNumEntries()) && isValidCacheInfo(cacheInfo))
    {
        const uint baseAddr = float2CacheEntryAddress(cacheInfo, spatialHashGrid.getStrideElementsPerEntry()) + float2CacheAddress(element);
        spatialHashGrid.addValueAndIncrementCounterFloat2(baseAddr, valueToAdd);
        spatialHashGrid.updateTimestamp(cacheInfo, frameNumber);
    }
}

// not used, ray guide cache element size is 8 bytes
void updateSpatialHashVoxelElement4<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    CacheInfo cacheInfo,
    float4 valueToAdd,
    uint element,
    uint frameNumber
)
{
    if (spatialHashGrid.getNumEntries() == 0)
    {
        return;
    }

    if ((cacheInfo < spatialHashGrid.getNumEntries()) && isValidCacheInfo(cacheInfo))
    {
        spatialHashGrid.updateTimestamp(cacheInfo, frameNumber);
        uint baseAddr = float4CacheEntryAddress(cacheInfo, spatialHashGrid.getStrideElementsPerEntry()) + float4CacheAddress(element);
        spatialHashGrid.addValueAndIncrementCounterFloat4(baseAddr, valueToAdd);
    }
}

uint computeHashCodeForShadingKey<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    half jitter[6],
    const float3 hitPoint,
    const float3 shadingNormal,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float coneRadius,
    float distance,
    const float3 triangleNormal,
    const uint frameNumber
)
{
    CacheInfo newCacheSlot = CACHED_PT_INVALID_HASH_ENTRY;

    if (spatialHashGrid.getDistanceOverride() != 0.f)
    {
        distance = spatialHashGrid.getDistanceOverride();
    }

    const HashKey shadingKey = computeSpatialHash(
        spatialHashGrid, hitPoint, shadingNormal, sceneBBoxMin, sceneBBoxMax, jitter, coneRadius, distance, triangleNormal
    );

    const uint hashCode = hash(shadingKey);

    return hashCode;
}

CacheInfo createSpatialHashVoxel<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    half jitter[6],
    const float3 hitPoint,
    const float3 shadingNormal,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float coneRadius,
    float distance,
    const float3 triangleNormal
)
{
    CacheInfo newCacheSlot = CACHED_PT_INVALID_HASH_ENTRY;
    if (spatialHashGrid.getNumEntries() == 0)
    {
        return newCacheSlot;
    }

    if (spatialHashGrid.getDistanceOverride() != 0.f)
    {
        distance = spatialHashGrid.getDistanceOverride();
    }

    const HashKey shadingKey = computeSpatialHash(
        spatialHashGrid, hitPoint, shadingNormal, sceneBBoxMin, sceneBBoxMax, jitter, coneRadius, distance, triangleNormal
    );
    const uint hashCode = hash(shadingKey);
    const bool successful = insertIntoHashMap(spatialHashGrid, shadingKey, hashCode, newCacheSlot);
    return newCacheSlot;
}

CacheInfo createSpatialHashVoxelMatID<SpatialHashGrid : ISpatialHashGrid>(
    SpatialHashGrid spatialHashGrid,
    half jitter[6],
    const float3 hitPoint,
    const float3 shadingNormal,
    const float3 sceneBBoxMin,
    const float3 sceneBBoxMax,
    const float coneRadius,
    float distance,
    const float3 triangleNormal,
    const uint materialID
)
{
    CacheInfo newCacheSlot = CACHED_PT_INVALID_HASH_ENTRY;
    if (spatialHashGrid.getNumEntries() == 0)
    {
        return newCacheSlot;
    }

    if (spatialHashGrid.getDistanceOverride() != 0.f)
    {
        distance = spatialHashGrid.getDistanceOverride();
    }

    const HashKey shadingKey = computeSpatialHashMatID(
        spatialHashGrid, hitPoint, shadingNormal, sceneBBoxMin, sceneBBoxMax, jitter, coneRadius, distance, triangleNormal, materialID
    );
    const uint hashCode = hash(shadingKey);
    const bool successful = insertIntoHashMap(spatialHashGrid, shadingKey, hashCode, newCacheSlot);
    return newCacheSlot;
}

float4 readSpatialHashVoxel<SpatialHashGrid : ISpatialHashGrid>(SpatialHashGrid spatialHashGrid, CacheInfo cacheInfo)
{
    if (spatialHashGrid.getNumEntries() == 0)
    {
        // Should never happen, return invalid color to mark unexpected path
        return float4(0.f, 1e18f, 0.f, 0.f); // read as CARB_ASSERT(false);
    }

    float4 result;
    if (isValidCacheInfo(cacheInfo))
    {
        // Read values from RWCacheValues which contains results from previous frames.
        const uint baseAddr = float4CacheAddress(cacheInfo);
        result = spatialHashGrid.readCacheValueFloat4(baseAddr);
    }
    else
    {
        result = float4(0.f, 0.f, 0.f, 0.f);
    }
    return result;
}

float2 readSpatialHashVoxelElement<SpatialHashGrid : ISpatialHashGrid>(SpatialHashGrid spatialHashGrid, CacheInfo cacheInfo, uint element)
{
    if (spatialHashGrid.getNumEntries() == 0)
    {
        // Should never happen, return invalid color to mark unexpected path
        return float2(0.f, 1e18f); // read as CARB_ASSERT(false);
    }

    float2 result;
    if (isValidCacheInfo(cacheInfo))
    {
        // Read values from RWCacheValues which contains results from previous frames.
        const uint baseAddr = float2CacheEntryAddress(cacheInfo, spatialHashGrid.getStrideElementsPerEntry()) + float2CacheAddress(element);
        result = spatialHashGrid.readCacheValueFloat2(baseAddr);
    }
    else
    {
        result = float2(0.f, 0.f);
    }
    return result;
}

float4 readSpatialHashVoxelElement4<SpatialHashGrid : ISpatialHashGrid>(SpatialHashGrid spatialHashGrid, CacheInfo cacheInfo, uint element)
{
    if (spatialHashGrid.getNumEntries() == 0)
    {
        // Should never happen, return invalid color to mark unexpected path
        return float4(0.f, 1e18f, 0.f, 0.f); // read as CARB_ASSERT(false);
    }

    float4 result;
    if (isValidCacheInfo(cacheInfo))
    {
        // Read values from RWCacheValues which contains results from previous frames.
        const uint baseAddr = float4CacheEntryAddress(cacheInfo, spatialHashGrid.getStrideElementsPerEntry()) + float4CacheAddress(element);
        result = spatialHashGrid.readCacheValueFloat4(baseAddr);
    }
    else
    {
        result = float4(0.f, 0.f, 0.f, 0.f);
    }
    return result;
}

/**
 * Compute an aspect-ratio corrected pixel angle in radians subtended by a pixel.
 */
// const float computePixelAngleInRad(const ViewParams viewParams)
// {
//     const float pixelAngle = max(viewParams.fovxInRadians / viewParams.renderTargetHeight,
//                                  viewParams.fovxInRadians * viewParams.aspectRatio / float(viewParams.renderTargetWidth));
//     return pixelAngle;
// }

#if 0
/// A different metric for determining the cell size. Taken from the AO Spatial Hashing demo from Pascal.
/// Does not seem to be as appropriate as the current metric but may be useful in the future.
float getFeatureSizeInWorldUnits(const ViewParams viewParams, float distance, float featureSizeInPixels, float minFeatureSize)
{
    const float pixelAngle = computePixelAngleInRad(viewParams);

    // incorporate user-defined featureSizeInPixels
    const float featureSize = tan(pixelAngle * featureSizeInPixels) * distance;

    // apply logarithmic stepping
    float log2Size = log2(featureSize / minFeatureSize);
    float featureSizeRound = exp2(floor(log2Size)) * minFeatureSize;
    return featureSizeRound;
}
#endif
