// Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
#include "Utils/NVAPI.slangh"

#define OMNI_NVAPI_SHADER_EXT 1

// Converts two 32-bit unsigned integers into a uint64_t type,
// with the x component containing the low 32 bits and y component the high 32 bits.
uint64_t Uint2ToUint64(uint2 value32)
{
    return (uint64_t)(((uint64_t)value32.y << 32) | (uint64_t)value32.x);
}

// Converts a uint64_t type into two 32-bit unsigned integers,
// with the x component containing the low 32 bits and y component the high 32 bits.
uint2 Uint64ToUint2(uint64_t value64)
{
    return uint2(uint(value64 & 0xffffffff), uint(value64 >> 32));
}

/// Atomic Helpers that use NVAPI for D3D12 or Slang for Vulkan
///
void RtxInterlockedCompareExchangeU64(
    RWByteAddressBuffer uav, uint byteAddress, uint64_t compareValue, uint64_t value, out uint64_t outOldValue)
{
#if OMNI_NVAPI_SHADER_EXT
    uav.InterlockedCompareExchange64(byteAddress, compareValue, value, outOldValue);
    // uint2 oldValue =
    //     NvInterlockedCompareExchangeUint64(uav, byteAddress, Uint64ToUint2(compareValue), Uint64ToUint2(value));
    // outOldValue = Uint2ToUint64(oldValue);
#else
    uav.InterlockedCompareExchangeU64(byteAddress, compareValue, value, outOldValue);
#endif
}

// void RtxInterlockedCompareExchangeU64(
//     RWByteAddressBuffer uav, uint byteAddress, uint2 compareValue, uint2 value, out uint2 outOldValue)
// {
//     uint2 oldValue =
//         NvInterlockedCompareExchangeUint64(uav, byteAddress, compareValue, value);
//     outOldValue = oldValue;
// }

void RtxInterlockedExchangeU64(RWByteAddressBuffer uav, uint byteAddress, uint64_t value)
{
#if OMNI_NVAPI_SHADER_EXT
    NvInterlockedExchangeUint64(uav, byteAddress, Uint64ToUint2(value));
#else
    uav.InterlockedExchangeU64(byteAddress, value);
#endif
}

void RtxInterlockedAddF32(RWByteAddressBuffer uav, uint byteAddress, float value)
{
#if OMNI_NVAPI_SHADER_EXT
    NvInterlockedAddFp32(uav, byteAddress, value);
#else
    uav.InterlockedAddF32(byteAddress, value);
#endif
}

void RtxInterlockedAddUint64(RWByteAddressBuffer uav, uint byteAddress, uint64_t value)
{
#if OMNI_NVAPI_SHADER_EXT
    NvInterlockedAddUint64(uav, byteAddress, Uint64ToUint2(value));
#else
    // Vulkan is limited to int64_t
    uav.InterlockedAddI64(byteAddress, (int64_t)value);
#endif
}
