// Copyright (c) 2019-2020, NVIDIA CORPORATION.  All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
#pragma once

#include "Utils/HostDeviceShared.slangh"
BEGIN_NAMESPACE_FALCOR

#include "SpatialHashGridMacros.slangh"
#include "Utils/Math/MathConstants.slangh"

//#include "ParameterBlock.h"

/// Based on "Online path sampling control with progressive spatio-temporal filtering" by Jacopo Pantaleoni
/// Important functions for using the hash are
/// SpatialHashGridUtils.hlsl::createSpatialHashVoxel(...) - Stores a voxel in the grid (if it doesnt exists) and returns handle to it
/// SpatialHashGridUtils.hlsl::updateSpatialHashVoxel(...) - Updates the "RWNewCacheValues" for a given handle
/// SpatialHashGridUtils.hlsl::readSpatialHashVoxel(...) - Returns the "RWCacheValues" for a given handle
/// SpatialGrid.cs.hlsl handles the merging of new entries and eviction of old ones

#ifdef HOST_CODE
enum class DirectionalDistType
{
    Histogram = SPATIAL_HASH_GRID_TYPE_HISTOGRAM,
    movMF = SPATIAL_HASH_GRID_TYPE_MOVMF,
    Quadtree = SPATIAL_HASH_GRID_TYPE_QUADTREE,
    GT = SPATIAL_HASH_GRID_TYPE_GT,
};

FALCOR_ENUM_INFO(DirectionalDistType, {
    { DirectionalDistType::Histogram, "Histogram" },
    { DirectionalDistType::movMF, "movMF" },
    { DirectionalDistType::Quadtree, "Quadtree" },
    { DirectionalDistType::GT, "GT" },
});
FALCOR_ENUM_REGISTER(DirectionalDistType);

// Layout for the RWVoxelSizeParams buffer
enum SpatialHashGridVoxelSizeParams
{
    eSpatialGridParamVoxelSize = 0, // The voxel size that should be used (that can be different than the UI setting, see `calculateVoxelSize`
    eSpatialGridParamLastFrameUpdated, // The last frame at which the `calculateVoxelSize` was invoked (it is invoked every once in a while)
    eSpatialGridParamCount,
};

#endif

#ifdef HOST_CODE
enum SpatialHashGridParamsFlags
{
    eSpatialHashGridDimUnusedEnties = 1 << 0, // entries that have not been updated will be dimmed at the end of the frame (LC+RIS does that, as RIS filters out "backfacing" lights)
    eSpatialHashGridDontResolveConflicts = 1 << 1, // assumes "no conflicts" (if there are, data gets mixed as if there is none)
    eSpatialHashGridConeBasedSpatialHash = 1 << 2, // use the cone based spatial hash function (coming from Jacopo)
    eSpatialHashGridDistanceBasedSpatialHash = 1 << 3, // use distsance based spatial hash function (coming from iray)
};
#endif

#ifndef HOST_CODE
enum class DirectionalDistType
{
    Histogram = SPATIAL_HASH_GRID_TYPE_HISTOGRAM,
    movMF = SPATIAL_HASH_GRID_TYPE_MOVMF,
    Quadtree = SPATIAL_HASH_GRID_TYPE_QUADTREE,
    GT = SPATIAL_HASH_GRID_TYPE_GT,
};

import Utils.Math.ShadingFrame;

inline float3x3 onb(float3 n)
{
    float sign = n.z < 0 ? -1 : 1;
    float a = -1.0f / (sign + n.z);
    float b = n.x * n.y * a;

    return { 1.0f + sign * n.x * n.x * a, b, n.x, sign * b, sign + n.y * n.y * a, n.y, -sign * n.x, -n.y, n.z };
}

float VMFPdf(float k, float dot)
{
    float e1 = 2 * M_PI * (1 - exp(-2 * k));
    float e2 = exp(k * (dot - 1));
    return k / e1 * e2;
}

struct vMF
{
    float3 direction;
    float kappa;

    __init()
    {
        direction = float3(0);
        kappa = 0;
    }

    bool isValid() { return kappa > 0; }

    float3 sample(float2 rnd)
    {
        float W = 1 + log(rnd.y + (1 - rnd.y) * exp(-2 * kappa)) / kappa;
        float W2 = sqrt(1 - W * W);

        float3 dir = { W2 * cos(2 * M_PI * rnd.x), W2 * sin(2 * M_PI * rnd.x), W };

        return mul(onb(direction), dir);
    }

    float cosQuantile(float q) { return 1 + log(q + (1 - q) * exp(-2 * kappa)) / kappa; }

    float pdf(float3 dir) { return VMFPdf(kappa, dot(direction, dir)); }
};


struct movMF
{
    vMF vmfs[K];
    float weights[K];

    __init()
    {
        for (uint k = 0; k < K; k++)
        {
            vmfs[k].direction = float3(0);
            vmfs[k].kappa = 0;
            weights[k] = 0;
        }
    }

    float pdf(const float3 dir)
    {
        float pdf = 0;
        for (uint k = 0; k < K; k++)
        {
            if (weights[k] > 0.0f) pdf += weights[k] * vmfs[k].pdf(dir);
        }
        return pdf;
    }

    float3 sample(float3 rnd)
    {
        float cumulativeWeight = 0.0f;
        uint selected = 0;
        for (uint k = 0; k < K; k++)
        {
            cumulativeWeight += weights[k];
            if (rnd.x <= cumulativeWeight)
            {
                selected = k;
                break;
            }
        }
        return vmfs[selected].sample(rnd.yz);
    }
}

#define SCREEN_SPACE_VMF_LOBES_COUNT 4
// #define SCREEN_SPACE_VMF_LOBES_COUNT 8

struct movMFSS
{
    vMF vmfs[SCREEN_SPACE_VMF_LOBES_COUNT];
    float weights[SCREEN_SPACE_VMF_LOBES_COUNT];

    __init(ShadingFrame frame)
    {
        if (SCREEN_SPACE_VMF_LOBES_COUNT == 4)
        {
            float thetaValues[2] = { M_PI / 8, 3 * M_PI / 8 };
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
            for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
            {
                vMF vmf;
                vmf.direction = frame.fromLocal(directions[k]);
                vmf.kappa = 50.0f;
                vmfs[k] = vmf;
                weights[k] = 1.0f / SCREEN_SPACE_VMF_LOBES_COUNT;
            }
        }
        else if (SCREEN_SPACE_VMF_LOBES_COUNT == 8)
        {
            float thetaValues[2] = { M_PI / 8, 3 * M_PI / 8 };
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
            for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
            {
                vMF vmf;
                vmf.direction = frame.fromLocal(directions[k]);
                vmf.kappa = 50.0f;
                vmfs[k] = vmf;
                weights[k] = 1.0f / SCREEN_SPACE_VMF_LOBES_COUNT;
            }
        }
    }

    float pdf(const float3 dir)
    {
        float pdf = 0;
        for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
        {
            if (weights[k] > 0.0f) pdf += weights[k] * vmfs[k].pdf(dir);
        }
        return pdf;
    }

    float3 sample(float3 rnd)
    {
        float cumulativeWeight = 0.0f;
        uint selected = 0;
        for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
        {
            cumulativeWeight += weights[k];
            if (rnd.x <= cumulativeWeight)
            {
                selected = k;
                break;
            }
        }
        return vmfs[selected].sample(rnd.yz);
    }
}

struct movMFSSGenerator
{
    float N;
    float sumOfWeights[SCREEN_SPACE_VMF_LOBES_COUNT];
    float totalW;
    float3 sumofWeightedDirections[SCREEN_SPACE_VMF_LOBES_COUNT];
    // movMFSS oldMovMF;

    __init()
    {
        N = 0.f;
        totalW = 0.f;
        for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
        {
            sumOfWeights[k] = 0.f;
            totalW = 0.f;
            sumofWeightedDirections[k] = float3(0.f);
        }
    }

    [mutating]
    void resetSufficientStatistics()
    {
        N = 0.f;
        totalW = 0.f;
        for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
        {
            sumOfWeights[k] = 0.f;
            sumofWeightedDirections[k] = float3(0.f);
        }
    }

    bool hasSufficientStatistics()
    {
        return N > 0;
    }

    [mutating]
    void add(float3 direction, float w, movMFSS oldMovMF)
    {
        const float pdf = oldMovMF.pdf(direction);
        // N = min(N + 1, 1024);
        N += 1;
        // float alpha = pow(N, -0.7f);
        // totalW = lerp(totalW, w, alpha);
        totalW += w;
        // const float scaleFactor = N == 1 ? 1.0f : N / (N - 1);
        for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
        {
            const float responsibility = oldMovMF.weights[k] > 0.0f ? oldMovMF.weights[k] * oldMovMF.vmfs[k].pdf(direction) / pdf : 0.0f;
            const float weight = w * responsibility;
            // sumOfWeights[k] = lerp(sumOfWeights[k], weight, alpha);
            // sumofWeightedDirections[k] = lerp(sumofWeightedDirections[k], weight * direction, alpha);
            sumOfWeights[k] += weight;
            sumofWeightedDirections[k] += weight * direction;
        }
    }

    [mutating]
    movMFSS getMovMF(ShadingFrame frame)
    {
        movMFSS movmf = movMFSS(frame);
        if (N > SCREEN_SPACE_VMF_LOBES_COUNT)
        {
            const float weightPrior = 0.01f;
            const float NPrior = 0.2f;
            const float rPrior = 0.0f;
            for (uint k = 0; k < SCREEN_SPACE_VMF_LOBES_COUNT; k++)
            {
                const float length = length(sumofWeightedDirections[k]);
                movmf.vmfs[k].direction = length > 0.0f ? sumofWeightedDirections[k] / length : movmf.vmfs[k].direction;

                const float mixturingWeight = sumOfWeights[k] / totalW;
                const float mixturingWeightWithPrior = (mixturingWeight + weightPrior) / (1.0f + weightPrior * SCREEN_SPACE_VMF_LOBES_COUNT);

                float r_ = length / sumOfWeights[k];

                r_ = (r_* mixturingWeightWithPrior * N + rPrior * NPrior) / (mixturingWeightWithPrior * N + NPrior);
                r_ = min(r_, 0.9999f);

                const float kappa = (3.0f * r_ - r_ * r_ * r_) / (1.0f - r_ * r_);
                movmf.vmfs[k].kappa = length > 0.0f ? max(min(kappa, 10000.0f), 1e-2f) : movmf.vmfs[k].kappa;
                movmf.weights[k] = mixturingWeightWithPrior;
            }
        }
        return movmf;
    }
}

// struct Quadtree
// {
//     QuadtreeNode nodes[TOTAL_QUADTREE_NODES];
//     float energy;

//     struct QuadtreeNode
//     {
//         float energy;
//         uint4 childrenIndices;

//         __init()
//         {
//             energy = 0;
//             childrenIndices = uint4(0);
//         }

//         bool isLeaf() { return all(childrenIndices == 0); }

//         void build()
//         {
//             if (isLeaf())
//             {
//                 return;
//             }

//             energy = 0;
//             for (uint i = 0; i < 4; i++)
//             {
//                 nodes[childrenIndices[i]].build();
//                 energy += nodes[childrenIndices[i]].energy;
//             }
//         }
//     }

//     __init()
//     {
//         for (uint i = 0; i < TOTAL_QUADTREE_NODES; i++)
//         {
//             nodes[i].energy = 0;
//             nodes[i].childrenIndices = uint4(0);
//         }
//         energy = 0;
//     }

//     [mutating]
//     void init()
//     {
//         for (uint i = 0; i < TOTAL_QUADTREE_NODES - TOTAL_QUADTREE_LEAVES; i++)
//         {
//             nodes[i].childrenIndices[0] = i * 4 + 1;
//             nodes[i].childrenIndices[1] = i * 4 + 2;
//             nodes[i].childrenIndices[2] = i * 4 + 3;
//             nodes[i].childrenIndices[3] = i * 4 + 4;
//         }

//         for (uint i = 0; i < TOTAL_QUADTREE_NODES; i++)
//         {
//             nodes[i].energy = 0;
//         }
//         energy = 0;
//     }

//     [mutating]
//     void build()
//     {
//         QuadtreeNode root = nodes[0];
//         root.build(nodes);
//         energy = root.energy;
//     }

// }

struct SpatialHashGridParams
{
    uint        numEntries;                 ///< The total count of entries that the spatial grid can store
    float       temporalReuse;              ///< Samples from how many frames to use
    float       temporalAlpha;              ///< How to blend the samples between old and new frames
    uint        frameNumber;                ///< Used for comparison while evicting entries

    uint        maxAgeForEviction;          ///< Used for age test while evicting entries
    uint        enableSpatialJitter;               ///< 1 if jittering should be used (jittering the voxel that we use will transform grid-like artifacts into noise
    uint        enableLODJitter;               ///< 1 if LOD jittering should be used
    uint        enableDirectionalJitter;    ///< 1 if directional jittering should be used, only applied to light cache
    uint        enableNanChecks;            ///< 1 if nan checks should be used for corner cases in light caching

    uint        showDebugView;              ///< 1 if we output debug data in the final frame
    uint        voxelSize;                  ///< Initial scale factor for the spatial hash voxel size, use the auto adjusted value from RWVoxelSizeParams instead
    uint        clampVoxelSize;             ///< Value to clamp the voxel size from below

    uint distanceBasedHashP0;     // valid if distance-based spatial hash is used
    uint distanceBasedHashP1;     // valid if distance-based spatial hash is used
    uint strideElementsPerEntry;  // The total number of element slots allocated per entry in the spatial hash, numElementsPerEntry is equal or smaller than it
                                  // This allow use to do more aggrisive reallocation strategy, like + 4/8 each time, instead of 1 by 1,
                                  // and thus save reallocation if numElementsPerEntry < strideElementsPerEntry.
    uint numElementsPerEntry;     // The total number of elements stored/used per entry in the spatial hash

    float       retrace;                    ///< Rays with length below this (in scene units) fallback to brute-force (prevents light leaks nears edges)
    uint        algmType;                   ///< Shader code is parameterized by the algorithm using the spatial hash (e.g Light Cache)
    uint        flags;                      ///< Of type `SpatialHashGridParamsFlags`
    uint        entryStride;                ///< In LC, we store each voxel & lights in 3D tex `RWCacheAuxBuffer`
                                            /// Each voxel gets mapped to unique `(x, y)` pair, lights are in `z` depth
                                            /// As we can't store more than 2k z elements,  we allocate multiple consecutive
                                            /// (x,y)` locations all as one long light list. This tells how many consecutive locations each voxel uses.

    float distanceOverride; // valid id distance-based spatial hash is used. Override for the distance that the renderer uses to limit the min voxel size

    uint useReSTIRSamples;

    RWByteAddressBuffer RWHashMapKey; ///< 64 bit hash key. Two consecutive elements form the key (no uint64_t in Slang)
    RWStructuredBuffer<uint>  RWVoxelSizeParams;   ///< Aux params for the cache - see `enum SpatialHashGridVoxelSizeParams`
    RWStructuredBuffer<uint> RWTimeStamps;         ///< For each entry, what was the last frame that modified it
    RWStructuredBuffer<uint> RWOverrideFlags;      ///< Is the entry overriden?
    RWByteAddressBuffer       RWCacheValues;       ///< The cached values (float3) .w is the number of values accumulated in that entry
    RWByteAddressBuffer       RWNewCacheValues;    ///< New cache entries gather during current frame. They will be merged RWCacheValues after frame end.
    RWByteAddressBuffer       RWHashTableCounter;  ///< Atomic counter used for cache entries
    RWTexture3D<float> RWCacheAuxBuffer; ///< Auxiliary buffer used for certain algorithms (e.g. Light Cache). We use tex as we want unorm
    RWStructuredBuffer<movMF> RWMoVMFBuffer; ///< Buffer for movMF
};

typedef SpatialHashGridParams RayGuideSpatialHashParams;
ParameterBlock<SpatialHashGridParams> gSpatialHashGridParams;
#endif

END_NAMESPACE_FALCOR
