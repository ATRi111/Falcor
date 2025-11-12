// Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
// #include "../ShadersCommon.h"
// #define SHADER_PIPE SHADER_PIPE_COMPUTE
// #define SHADER_TYPE SHADER_TYPE_COMPUTE

// #include "../../carb/GraphicsShaders.h"
// #include "../SpatialHashGridParamBlocks.h"
// #include "../utils/Packing.hlsl"

import SpatialHashGridBufferUtils;
import SpatialHashGridParams;
#include "SpatialHashGridMacros.slangh"
import Utils.Debug.PixelDebug;
import Rendering.Utils.PixelStats;
#include "Utils/Math/MathConstants.slangh"


// We store the Light Cache Aux(PDF) buffer in 3D tex in order to use unorm
// This converts the cacheInfo to coordinates in the tex where it will be stored
// see getLightIndexCoords for details on indexing individual lights
uint2 getAuxCoords(uint cacheInfo)
{
    const uint stride = gSpatialHashGridParams.entryStride;
    const uint x = (cacheInfo * stride) % MAX_3D_TEX_WIDTH;
    const uint y = (cacheInfo * stride) / MAX_3D_TEX_WIDTH;
    return uint2(x, y);
}

// In LC, we store each voxel & lights in 3D tex `RWCacheAuxBuffer`
// Each voxel gets mapped to unique `(x, y)` pair, lights are in `z` depth
// As we can't store more than 2k z elements,  we allocate multiple consecutive
// `(x,y)` locations all as one long light list. This tells how many consecutive locations each voxel uses.
uint2 getLightIndexCoords(uint lightIndex)
{
    return uint2((lightIndex < MAX_3D_TEX_WIDTH ? 0 : lightIndex / MAX_3D_TEX_WIDTH), lightIndex % MAX_3D_TEX_WIDTH);
}

void removeSlotFromHashMap(SpatialHashGridParams spatialHashParams, uint cacheSlot)
{
    setCacheEntryUint2(spatialHashParams.RWHashMapKey, cacheSlot * 8, uint2(CACHED_PT_INVALID_HASH_ENTRY, CACHED_PT_INVALID_HASH_ENTRY));

    uint oldValue;
    spatialHashParams.RWHashTableCounter.InterlockedAdd(0, int(-1), oldValue);
}

void buildCDFOverElements(uint baseAddr, uint numElements, float sum)
{
    const uint2 auxCoords = getAuxCoords(baseAddr);
    if (sum < 1e-3f)
    {
        // Something is wrong (the sum of the PDFs is too small value, this is usually a bug)
        // Add a guard by building uniform light pick CDF in that case
        for (int i = 0; i < numElements; ++i)
        {
            const uint2 lightIndexCoords = getLightIndexCoords(i);
            gSpatialHashGridParams
                .RWCacheAuxBuffer[float3(auxCoords.x + lightIndexCoords.x, auxCoords.y, lightIndexCoords.y)] =
                (float)(i + 1) / (float)numElements;
        }
    }
    else
    {
        // TODO was this a general fix why would a pdf be zero?
        const float minPdf = 1e-5; // Makes sure the PDF is non-zero in order for inverse CDF to function properlly
        float adjSum = sum + minPdf * numElements;
        float cdf = 0.f;
        for (int i = 0; i < numElements; ++i)
        {
            const uint2 lightIndexCoords = getLightIndexCoords(i);
            const float pdf =
                (minPdf + gSpatialHashGridParams.RWCacheAuxBuffer[float3(
                                            auxCoords.x + lightIndexCoords.x, auxCoords.y, lightIndexCoords.y)]) /
                adjSum;
            cdf += pdf;

            gSpatialHashGridParams
                .RWCacheAuxBuffer[float3(auxCoords.x + lightIndexCoords.x, auxCoords.y, lightIndexCoords.y)] = cdf;
        }
    }
    const uint2 lightIndexCoordsLast = getLightIndexCoords(numElements - 1);
    gSpatialHashGridParams
        .RWCacheAuxBuffer[float3(auxCoords.x + lightIndexCoordsLast.x, auxCoords.y, lightIndexCoordsLast.y)] = 1.0f;
}

// TODO do something about this it sticks out
// perhaps we need readers for all light cache buffers..
interface ICacheAuxBufferReader
{
    float readAuxBuffer(float3 index);
};

struct CacheAuxBufferReader : ICacheAuxBufferReader
{
    float readAuxBuffer(float3 index)
    {
        return gSpatialHashGridParams.RWCacheAuxBuffer[index];
    }
};

// -----------------------------------------------------------------------------
// Kernel for clearing all hash map related resources initially.
// -----------------------------------------------------------------------------
[numthreads(1024, 1, 1)]
void clearAllHashMapResourcesMain(uint launchIndex : SV_DispatchThreadID)
{
    if (launchIndex >= gSpatialHashGridParams.numEntries)
    {
        return;
    }

    gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eLastFrameUpdated] = gSpatialHashGridParams.frameNumber;
    gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eVoxelSize] = gSpatialHashGridParams.voxelSize;
#if 1
    //
    // Implementation if RWHashMapKey is RGRWByteAddressBuffer
    //
    // * 8 for uint2 addressing
    setCacheEntryUint2(gSpatialHashGridParams.RWHashMapKey, launchIndex * 8, uint2(CACHED_PT_INVALID_HASH_ENTRY, CACHED_PT_INVALID_HASH_ENTRY));

#endif

#if 0
    //
    // Implementation if RWHashMapKey is RGRWStructuredBuffer<uint>
    //

    gSpatialHashGridParams.RWHashMapKey[launchIndex * 2 + 0] = uint(CACHED_PT_INVALID_HASH_ENTRY);
    gSpatialHashGridParams.RWHashMapKey[launchIndex * 2 + 1] = uint(CACHED_PT_INVALID_HASH_ENTRY);
#endif

    gSpatialHashGridParams.RWTimeStamps[launchIndex] = 0;
    gSpatialHashGridParams.RWOverrideFlags[launchIndex] = 0; // reset override flags

    const uint baseAddr = float2CacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);
    clearAllCacheEntryElementsFloat2(
        gSpatialHashGridParams.RWCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
    clearAllCacheEntryElementsFloat2(
        gSpatialHashGridParams.RWNewCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);

    // since we don't use ray guide for frame 0, we don't need to build a CDF

    if (launchIndex == 0)
    {
        gSpatialHashGridParams.RWHashTableCounter.Store(0, uint(0));
    }
}

// -----------------------------------------------------------------------------
// Kernel for clearing the hash map related resources for a new frame and previous frame information remains
// untouched.
// -----------------------------------------------------------------------------
[numthreads(1024, 1, 1)]
void clearNewHashMapResourcesMain(uint launchIndex : SV_DispatchThreadID)
{
    if (launchIndex >= gSpatialHashGridParams.numEntries)
    {
        return;
    }

    int2 pixel = int2(launchIndex % 256, launchIndex / 256);
    printSetPixel(pixel);
    logSetPixel(pixel);

    print("launchIndex", launchIndex); // TODO: make printing work!!!

    gSpatialHashGridParams.RWOverrideFlags[launchIndex] = 0; // reset override flags

    const uint currentTimeStamp = (gSpatialHashGridParams.RWTimeStamps[launchIndex]);
    if (currentTimeStamp != gSpatialHashGridParams.frameNumber - 1) // only need to clear if last frame writes
    {
        return;
    }

    //
    const uint baseAddr = float2CacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);
    clearAllCacheEntryElementsFloat2(
        gSpatialHashGridParams.RWNewCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
}

#define SPATIAL_HASH_SIZE_THRESHOLD 0.8f

int getNumAllocatedEntries()
{
    return gSpatialHashGridParams.RWHashTableCounter.Load(0);
}

// If the spatial hash gets relatively full, increase the voxel size
// We run this kernel rarely, as we want to give time to `evictEntriesFromHashMapMain` to evict entries
[numthreads(1, 1, 1)]
void calculateVoxelSize(uint launchIndex : SV_DispatchThreadID) // not used by rayguide
{
    if (launchIndex != 0)
    {
        return;
    }
    const uint frameNumber = gSpatialHashGridParams.frameNumber;
    const uint lastFrameUpdated = gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eLastFrameUpdated];
    const bool recentlyUpdated = abs((int)frameNumber - (int)lastFrameUpdated) < (gSpatialHashGridParams.maxAgeForEviction * 2);

    const bool almostFull = (float)getNumAllocatedEntries() > 0.85*(float)asuint(gSpatialHashGridParams.numEntries);
    if (almostFull && !recentlyUpdated)
    {
        const uint STEP = 10;
        const uint MAX_DIFF = 50;

        // In case we already increased voxel size, compute by how much so we can take that into account in the current increase
        const uint diff = clamp(gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eVoxelSize] - gSpatialHashGridParams.voxelSize, 0, MAX_DIFF);
        gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eVoxelSize] = gSpatialHashGridParams.voxelSize + diff + STEP;
        gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eLastFrameUpdated] = frameNumber;
    }
}

// -----------------------------------------------------------------------------
// Kernel for evicting entries from the hash map (see prune_hashmap_kernel).
// -----------------------------------------------------------------------------
[numthreads(1024, 1, 1)]
void evictEntriesFromHashMapMain(uint launchIndex : SV_DispatchThreadID)
{
    if (launchIndex >= gSpatialHashGridParams.numEntries)
    {
        return;
    }

    // @todo: This code needs to be verified.
    const uint invalidValue = CACHED_PT_INVALID_HASH_ENTRY;
#if 1
    //
    // Implementation if RWHashMapKey is RGRWByteAddressBuffer
    //
    const uint2 currentHashValue = uint2(gSpatialHashGridParams.RWHashMapKey.Load(launchIndex * 8 + 0),
        gSpatialHashGridParams.RWHashMapKey.Load(launchIndex * 8 + 4));
   // const uint2 currentHashValue = getCacheEntryUint2(gSpatialHashGridParams.RWHashMapKey, launchIndex * 8);


#endif
#if 0
    //
    // Implementation if RWHashMapKey is RGRWStructuredBuffer<uint>
    //
    const uint2 currentHashValue = uint2(gSpatialHashGridParams.RWHashMapKey[launchIndex * 2 + 0],
                                         gSpatialHashGridParams.RWHashMapKey[launchIndex * 2 + 1]);
#endif
    const uint numAllocatedEntries = getNumAllocatedEntries();
    const bool almostFull = (float)numAllocatedEntries >= (float)gSpatialHashGridParams.numEntries*.75f;
    if (!almostFull)
    {
        return;
    }
    if (all(currentHashValue != invalidValue))
    {
        const uint currentTimeStamp = (gSpatialHashGridParams.RWTimeStamps[launchIndex]); // the last time this is touched
        // currently not used by ray guide
        if (abs((int)gSpatialHashGridParams.frameNumber - (int)currentTimeStamp) > gSpatialHashGridParams.maxAgeForEviction)
        {
            removeSlotFromHashMap(gSpatialHashGridParams, launchIndex);

            const uint baseAddr = float2CacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);
            clearAllCacheEntryElementsFloat2(
                gSpatialHashGridParams.RWCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
        }
    }
}

void combineHashEntryValues(float temporalReuse, float temporalAlpha, uint baseAddr)
{
    const float4 newVal = getCacheEntryFloat4(gSpatialHashGridParams.RWNewCacheValues, baseAddr);
    if (newVal.w > 0.f)
    {
        const float4 oldVal = getCacheEntryFloat4(gSpatialHashGridParams.RWCacheValues, baseAddr);

        // compute the temporal average
        const float alpha = oldVal.w < 8 ?
                                newVal.w / (oldVal.w + newVal.w) :
                                temporalAlpha * max(sqrt(newVal.w / (oldVal.w + newVal.w)), 1.0f / temporalReuse);

        const float4 avgVal = float4(oldVal.x * (1.0f - alpha) + (newVal.x / newVal.w) * alpha,
                                     oldVal.y * (1.0f - alpha) + (newVal.y / newVal.w) * alpha,
                                     oldVal.z * (1.0f - alpha) + (newVal.z / newVal.w) * alpha,
                                     min(oldVal.w + newVal.w, (float)temporalReuse));

        // write back the computed average
        setCacheEntryFloat4(gSpatialHashGridParams.RWCacheValues, baseAddr, avgVal);
    }
    // probably don't need will call clear new anyways
    clearCacheEntryFloat4(gSpatialHashGridParams.RWNewCacheValues, baseAddr);
}

void combineHashEntryElementsValues(const float temporalReuse, const float temporalAlpha, uint numElements, uint baseAddr)
{
//     for (int i = 0; i < numElements; i++)
//     {
//         const float2 newVal = getCacheEntryElementFloat2(gSpatialHashGridParams.RWNewCacheValues, baseAddr, i);
//         const float2 oldVal = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i);

//         if (newVal.y > 0.f)
//         {
//             // We need something here that doesnt change PDFs quickly from frame to frame, this below is temp working solution
//             // Feel free to replace if you have a better one
//             const float alpha = oldVal.y < 8 ?
//                                 newVal.y / (oldVal.y + newVal.y) :
//                                 temporalAlpha * max(sqrt(newVal.y / (oldVal.y + newVal.y)), 1.0f / temporalReuse);

//             const float n = oldVal.x * (1.0f - alpha) + (newVal.x/newVal.y) * alpha;
// #if 0
//             float f = -oldVal.x + n;
//             const float C = 1.5f;
//             f = clamp(f, -C, C);
//             const float2 avgVal = float2(oldVal.x + f,
//                 min(oldVal.y + newVal.y, (float)temporalReuse));
// #else
//             const float total = min(oldVal.y + newVal.y, temporalReuse);
//             const float2 avgVal = float2(n, total);
// #endif

//             // write back the computed average
//             setCacheElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i, avgVal);
//         }
//         // not written in consecutive frames -> maybe zero (prevents fireflies)
//         // think about how to remove fireflies without this
//         // this is not good if our hash voxel are only touched by screen space primary hits (disocclusion noise problem)
//         else if (oldVal.x > .5f && (gSpatialHashGridParams.flags & SPATIAL_HASH_GRID_eSpatialHashGridDimUnusedEnties))
//         {
//             // We might need to "invalidate" entries that are not touched in a while for some use case - for example
//             // using light cache & RIS, light that is back-facing would never be picked (as RIS will filter it) and we will never "dimm" it out

//             // If a light hasnt been touched, gradually make it less important over time
//             setCacheElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i, oldVal * .8f);
//         }
// //     }
    for (int i = 0; i < numElements; i++)
    {
        const float2 newVal = getCacheEntryElementFloat2(gSpatialHashGridParams.RWNewCacheValues, baseAddr, i);
        const float2 oldVal = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i);

        const float2 avgVal = oldVal * 1.f + newVal * 1.f;

        setCacheElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i, avgVal);
    }
}

uint getContributingSampleCount(uint baseAddr)
{
    uint count = 0;
    for (int i = 0; i < gSpatialHashGridParams.numElementsPerEntry; ++i)
    {
        const float2 entry = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i);
        count += (uint)entry.y;
    }
    return count;
}

float getContribution(uint baseAddr)
{
    float contribution = 0.f;
    for (int i = 0; i < gSpatialHashGridParams.numElementsPerEntry; ++i)
    {
        const float2 entry = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddr, i);
        contribution += entry.x;
    }
    return contribution;
}

void swapHalf(inout half a, inout half b)
{
    const half tmp = a;
    a = b;
    b = tmp;
}

void swapInt(inout int a, inout int b)
{
    const int tmp = a;
    a = b;
    b = tmp;
}

int2 linearIndexTo2D(int index)
{
    return int2(index % 16, index / 16);
}

void computeRayGuideCDF(uint baseAddrValues, uint baseAddrCDF, uint sampleCount, uint launchIndex)
{
    const uint2 auxCoords = getAuxCoords(baseAddrCDF);

    const uint numBins = gSpatialHashGridParams.numElementsPerEntry;

    float pdfSum = 0.f;
    for (int i = 0; i < numBins; ++i)
    {
        const float2 pdfValue = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddrValues, i);
        if (pdfValue.x != pdfValue.y && pdfValue.y != 0.f)
            pdfSum += pdfValue.x / pdfValue.y;
        else
            pdfSum += pdfValue.x;
    }
    float eps = pdfSum / float(numBins) * 0.01f;

    pdfSum = 0.f;
    for (int i = 0; i < numBins; ++i)
    {
        const float2 pdfValue = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddrValues, i);
        if (pdfValue.x != pdfValue.y && pdfValue.y != 0.f)
            pdfSum += pdfValue.x / pdfValue.y + eps;
        else
            pdfSum += pdfValue.x + eps;
    }
    float normFactor = 1.f / (pdfSum / float(numBins));

    float cdf = 0.f;
    for (int i = 0; i < numBins; ++i)
    {
        const float2 pdfValue = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddrValues, i);
        float pdf;
        if (pdfValue.x != pdfValue.y && pdfValue.y != 0.f)
            pdf = (pdfValue.x / pdfValue.y + eps) * normFactor;
        else
            pdf = (pdfValue.x + eps) * normFactor;
        const uint2 lightIndexCoords = getLightIndexCoords(i);
        cdf += pdf * (1.f / float(numBins));

        gSpatialHashGridParams
            .RWCacheAuxBuffer[float3(auxCoords.x + lightIndexCoords.x, auxCoords.y, lightIndexCoords.y)] = cdf;
    }
    const uint2 lightIndexCoordsLast = getLightIndexCoords(numBins - 1);
    gSpatialHashGridParams
        .RWCacheAuxBuffer[float3(auxCoords.x + lightIndexCoordsLast.x, auxCoords.y, lightIndexCoordsLast.y)] = 1.0f;

    // // Samples contributing to this voxel in the last frame
    // float numSamplesFromVoxel = sampleCount;

    // // Get the normalization constant for the pdf
    // float pdfSumTemp = 0.f;
    // for (int i = 0; i < numBins; ++i)
    // {
    //     float2 entry = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddrValues, i);
    //     // if(launchIndex == 49664)
    //     // {
    //     //     int2 offset = linearIndexTo2D(i);
    //     //     gViewParams.DeveloperDebugTexture[2*offset + int2(100,100)] = float4(entry.xxx,1);
    //     //     gViewParams.DeveloperDebugTexture[2*offset + int2(101,100)] = float4(entry.xxx,1);
    //     //     gViewParams.DeveloperDebugTexture[2*offset + int2(100,101)] = float4(entry.xxx,1);
    //     //     gViewParams.DeveloperDebugTexture[2*offset + int2(101,101)] = float4(entry.xxx,1);
    //     //     gViewParams.DeveloperDebugTexture[offset + int2(200,100)] = float4(entry.yyy,1);
    //     // }
    //     pdfSumTemp += entry.x;
    // }

    // float minPdf = 1.0f / ((float)numBins * numSamplesFromVoxel);

    // // Get the normalization constant for the pdf considering bright bins only
    // float pdfSum = 0.f;
    // uint dimBinCount = 0;
    // for (int i = 0; i < numBins; ++i)
    // {
    //     float pdfValue = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddrValues, i).x;
    //     // If the pdf is too low we count it as a dim bin
    //     if ((pdfValue / pdfSumTemp) < minPdf)
    //     {
    //         dimBinCount++;
    //     }
    //     else
    //     {
    //         pdfSum += pdfValue;
    //     }
    // }

    // // The totalminpdf is just minpdf * dimLightCount, it is the total probability we are "allocating" for all dim bins
    // const float totalMinPdf = minPdf * (float)dimBinCount;

    // // Adjust the normalization constant to account for the insertion of totalMinPdf
    // /*
    //  *   p1 + p2 + p3 + p4 + p5 + p6...
    //  *   ---------------------------   =  1.0f
    //  *              pdfSum
    //  *
    //  *              pdfSum
    //  *   ---------------------------   =  adjustedPdfSum
    //  *       (1.0f - totalMinPdf)
    //  */
    // float adjustedPdfSum = pdfSum / (1.0f - totalMinPdf);

    // float sum = 0.f;
    // //float currentSum = 0.f;
    // for (int i = 0; i < numBins; ++i)
    // {
    //     // Check if original pdf falls below minpdf threshold
    //     float2 pdfValue = getCacheEntryElementFloat2(gSpatialHashGridParams.RWCacheValues, baseAddrValues, i);
    //     float wantedPDF = pdfValue.x;

    //     if ((wantedPDF / pdfSumTemp) < minPdf)
    //     {
    //         wantedPDF = minPdf;
    //     }
    //     else
    //     {
    //         // Renormalize all other pdfs with the adjusted normalizer
    //         wantedPDF = wantedPDF / adjustedPdfSum;
    //     }

    //     // what does currentSum do here???
    //     // float currentPDF = gSpatialHashGridParams.RWCacheAuxBuffer[float3(auxCoords.x, auxCoords.y, i)] - currentSum;
    //     // currentSum += currentPDF;

    //     // If spatial hash blending in combineHashEntryElementsValues does not satisfy needs we can use blending here
    //     // Must be removed if we use the optimization in LightCache that checks valid is forces 1/n sampling
    //     // instead use currentPDF = wantedPDF;
    //     // currentPDF = currentPDF + (wantedPDF - currentPDF) / 5;

    //     float currentPDF = wantedPDF;

    //     // TODO we should resolve these nans with a solid repro and fix, (note: nans show up blue in debug window)
    //     if (gSpatialHashGridParams.enableNanChecks)
    //     {
    //         if (isnan(currentPDF) || isinf(currentPDF) || currentPDF == 0)
    //             currentPDF = minPdf;
    //     }

    //     gSpatialHashGridParams.RWCacheAuxBuffer[float3(auxCoords.x, auxCoords.y, i)] = currentPDF;

    //     // Since we are using averging now with the spatial hash we could remove this and write 0 when we hit occluders
    //     // with shadow rays, that would more naturally bring down the pdf over time
    //     // Need to be careful that during spatial hash combine entries we don't rely heavily on old values since they
    //     // are being reduced here, maybe want to remove this
    //     //setCacheElementFloat2(
    //     //    gSpatialHashGridParams.RWCacheValues, baseAddrValues, i, float2(pdfValue.x * 0.85, pdfValue.y));

    //     sum += currentPDF;
    // }

    // buildCDFOverElements(baseAddrCDF, numBins, sum);
}

// -----------------------------------------------------------------------------
// Kernel for combining old cache and new cache to a single cache (see tr_average_kernel).
// -----------------------------------------------------------------------------
// After accumulation, the new cache is left unchanged and it will be cleaned before the new
// frame begins.
[numthreads(1024, 1, 1)]
void combineOldAndNewHashMapMain(uint launchIndex : SV_DispatchThreadID)
{
    if (launchIndex >= gSpatialHashGridParams.numEntries)
    {
        return;
    }

    const uint invalidValue = CACHED_PT_INVALID_HASH_ENTRY;
    const uint2 currentHashValue = getCacheEntryUint2(gSpatialHashGridParams.RWHashMapKey, launchIndex * 8);

    if (all(currentHashValue == uint2(invalidValue, invalidValue))) // check why hash value is invalid
        return;

    const float temporalReuse = gSpatialHashGridParams.temporalReuse;
    const float temporalAlpha = gSpatialHashGridParams.temporalAlpha;

    //  we only update if the entry is touched in current frame

    // const uint currentTimeStamp = (gSpatialHashGridParams.RWTimeStamps[launchIndex]); // the last time this is touched
    // if (currentTimeStamp < gSpatialHashGridParams.frameNumber)
    //     return;

    bool isOverride = gSpatialHashGridParams.RWOverrideFlags[launchIndex];
    if (isOverride) // clear everything if current entry overrides an existing one
    {
        const uint baseAddr = float2CacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);
        clearAllCacheEntryElementsFloat2(
            gSpatialHashGridParams.RWCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
    }

    const uint baseAddrValues = float2CacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);


    // Don't update if we don't have to
    // if (sampleCount == 0)
    //     return;

    combineHashEntryElementsValues(
            temporalReuse, temporalAlpha, gSpatialHashGridParams.numElementsPerEntry, baseAddrValues);

    uint sampleCount = getContributingSampleCount(baseAddrValues);
    if (getContribution(baseAddrValues) == 0.f)
        return;

    if (gSpatialHashGridParams.algmType == 0) //TODO:change this to define
    {
        // CDF requires different addressing
        const uint baseAddrCDF = launchIndex;
        computeRayGuideCDF(baseAddrValues, baseAddrCDF, sampleCount, launchIndex);
        clearAllCacheEntryElementsFloat2(
            gSpatialHashGridParams.RWNewCacheValues, baseAddrValues, gSpatialHashGridParams.strideElementsPerEntry);
    }
}

void initMoVMF(uint cacheInfo)
{
    movMF movmf;
    if (K == 4)
    {
        float thetaValues[2] = { M_PI / 4, 3 * M_PI / 4 };
        float phiValues[2] = { 0, M_PI };
        float3 directions[4];
        int index = 0;
        for (uint i = 0; i < 2; i++)
        {
            for (uint j = 0; j < 2; j++)
            {
                float theta = thetaValues[i];
                float phi = phiValues[j];
                directions[index] = float3(
                    sin(theta) * cos(phi),
                    sin(theta) * sin(phi),
                    cos(theta)
                );
                index++;
            }
        }
        for (uint k = 0; k < K; k++)
        {
            vMF vmf;
            vmf.direction = directions[k];
            vmf.kappa = 50.0f;
            movmf.vmfs[k] = vmf;
            movmf.weights[k] = 1.0f / K;
        }
    }
    else if (K == 8)
    {
        float thetaValues[2] = { M_PI / 4, 3 * M_PI / 4 };
        float phiValues[4] = { 0, M_PI / 2, M_PI, 3 * M_PI / 2 };
        float3 directions[8];
        int index = 0;
        for (uint i = 0; i < 2; i++)
        {
            for (uint j = 0; j < 4; j++)
            {
                float theta = thetaValues[i];
                float phi = phiValues[j];
                directions[index] = float3(
                    sin(theta) * cos(phi),
                    sin(theta) * sin(phi),
                    cos(theta)
                );
                index++;
            }
        }
        for (uint k = 0; k < K; k++)
        {
            vMF vmf;
            vmf.direction = directions[k];
            vmf.kappa = 50.0f;
            movmf.vmfs[k] = vmf;
            movmf.weights[k] = 1.0f / K;
        }
    }
    gSpatialHashGridParams.RWMoVMFBuffer[cacheInfo] = movmf;
}


[numthreads(1024, 1, 1)]
void initMoVMFMain(uint launchIndex : SV_DispatchThreadID)
{
    if (launchIndex >= gSpatialHashGridParams.numEntries)
    {
        return;
    }

    gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eLastFrameUpdated] = gSpatialHashGridParams.frameNumber;
    gSpatialHashGridParams.RWVoxelSizeParams[SPATIAL_HASH_VOXEL_PARAMS_eVoxelSize] = gSpatialHashGridParams.voxelSize;

    //
    // Implementation if RWHashMapKey is RGRWByteAddressBuffer
    //
    // * 8 for uint2 addressing
    setCacheEntryUint2(gSpatialHashGridParams.RWHashMapKey, launchIndex * 8, uint2(CACHED_PT_INVALID_HASH_ENTRY, CACHED_PT_INVALID_HASH_ENTRY));

    gSpatialHashGridParams.RWTimeStamps[launchIndex] = 0;
    gSpatialHashGridParams.RWOverrideFlags[launchIndex] = 0; // reset override flags

    const uint baseAddr = floatCacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);

    clearAllCacheEntryElementsFloat(
        gSpatialHashGridParams.RWCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
    clearAllCacheEntryElementsFloat(
        gSpatialHashGridParams.RWNewCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
    if (launchIndex == 0)
    {
        gSpatialHashGridParams.RWHashTableCounter.Store(0, uint(0));
    }

    // Initialize the movMF
    initMoVMF(launchIndex);
}

[numthreads(1024, 1, 1)]
void resolveMoVMFMain(uint launchIndex : SV_DispatchThreadID)
{
    if (launchIndex >= gSpatialHashGridParams.numEntries)
    {
        return;
    }

    const uint invalidValue = CACHED_PT_INVALID_HASH_ENTRY;
    const uint2 currentHashValue = getCacheEntryUint2(gSpatialHashGridParams.RWHashMapKey, launchIndex * 8);

    if (all(currentHashValue == uint2(invalidValue, invalidValue))) // check why hash value is invalid
        return;

    const uint baseAddr = floatCacheEntryAddress(launchIndex, gSpatialHashGridParams.strideElementsPerEntry);

    // Copy sufficient statistics from the newCache to cache
    for (int i = 0; i < gSpatialHashGridParams.numElementsPerEntry; i++)
    {
        const float newVal = getCacheEntryElementFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, i);
        const float oldVal = getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, i);

        float avgVal;
        if (gSpatialHashGridParams.useReSTIRSamples)
        {
            avgVal = oldVal * 0.f + newVal * 1.f;
        }
        else
        {
            avgVal = oldVal * 0.25f + newVal * 1.f;
        }
        setCacheElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, i, avgVal);
    }

    float N = getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, I_INDEX);
    if (N == 0.f) return;

    if (N < K)
    {
        clearAllCacheEntryElementsFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
        return;
    }

    float totalW = getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, TOTAL_WEIGHT_INDEX);

    float norm = 1.f;
    // if (!gSpatialHashGridParams.useReSTIRSamples)
    // {
    //     norm = 1.f / (totalW / N);
    // }
    // totalW *= norm;

    float3 sumofWeightedDirections[K];
    float sumOfWeights[K];
    for (uint k = 0; k < K; k++)
    {
        sumofWeightedDirections[k] = float3(getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, SUM_OF_WEIGHTED_DIRECTIONS_START_INDEX + k * SUM_OF_WEIGHTED_DIRECTIONS_STRIDE + 0),
            getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, SUM_OF_WEIGHTED_DIRECTIONS_START_INDEX + k * SUM_OF_WEIGHTED_DIRECTIONS_STRIDE + 1),
            getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr, SUM_OF_WEIGHTED_DIRECTIONS_START_INDEX + k * SUM_OF_WEIGHTED_DIRECTIONS_STRIDE + 2)) * norm;
        sumOfWeights[k] = getCacheEntryElementFloat(gSpatialHashGridParams.RWCacheValues, baseAddr,SUM_OF_WEIGHTED_DIRECTIONS_START_INDEX + k * SUM_OF_WEIGHTED_DIRECTIONS_STRIDE + 3) * norm;
    }

    movMF movmf = movMF();
    const float weightPrior = 0.01f;
    const float NPrior = 0.2f;
    const float rPrior = 0.0f;
    for (uint k = 0; k < K; k++)
    {
        const float length = length(sumofWeightedDirections[k]);
        movmf.vmfs[k].direction = length > 0.0f ? sumofWeightedDirections[k] / length : movmf.vmfs[k].direction;

        const float mixturingWeight = sumOfWeights[k] / totalW;
        const float mixturingWeightWithPrior = (mixturingWeight + weightPrior) / (1.0f + weightPrior * K);

        float r_ = length / sumOfWeights[k];

        r_ = (r_* mixturingWeightWithPrior * N + rPrior * NPrior) / (mixturingWeightWithPrior * N + NPrior);
        r_ = min(r_, 0.9999f);

        const float kappa = (3.0f * r_ - r_ * r_ * r_) / (1.0f - r_ * r_);

        movmf.vmfs[k].kappa = max(min(kappa, 10000.0f), 1e-2f);

        movmf.weights[k] = mixturingWeightWithPrior;
    }
    gSpatialHashGridParams.RWMoVMFBuffer[launchIndex] = movmf;

    clearAllCacheEntryElementsFloat(gSpatialHashGridParams.RWNewCacheValues, baseAddr, gSpatialHashGridParams.strideElementsPerEntry);
}
