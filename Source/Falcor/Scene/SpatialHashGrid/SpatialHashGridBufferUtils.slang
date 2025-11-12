// Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
//
// NVIDIA CORPORATION and its licensors retain all intellectual property
// and proprietary rights in and to this software, related documentation
// and any modifications thereto.  Any use, reproduction, disclosure or
// distribution of this software and related documentation without an express
// license agreement from NVIDIA CORPORATION is strictly prohibited.
//
#pragma once

// Byte addressing for a float4 in a float4 buffer
uint float4CacheAddress(uint cacheInfo)
{
    return cacheInfo * 16;
}

// Byte addressing for a float2 in a float2 buffer
uint float2CacheAddress(uint cacheInfo)
{
    return cacheInfo * 8;
}

// Byte addressing for a float in a float buffer
uint floatCacheAddress(uint cacheInfo)
{
    return cacheInfo * 4;
}

// Byte addressing for a float4 entry with multiple float4 elements
// Cannot be used for a specific element within an entry
uint float4CacheEntryAddress(uint cacheInfo, uint strideElementsPerEntry)
{
    return cacheInfo * 16 * strideElementsPerEntry;
}

// Byte addressing for a float2 entry with multiple float2 elements
// Cannot be used for a specific element within an entry
uint float2CacheEntryAddress(uint cacheInfo, uint strideElementsPerEntry)
{
    return cacheInfo * 8 * strideElementsPerEntry;
}

// Byte addressing for a float entry with multiple float elements
// Cannot be used for a specific element within an entry
uint floatCacheEntryAddress(uint cacheInfo, uint strideElementsPerEntry)
{
    return cacheInfo * 4 * strideElementsPerEntry;
}

uint uint2CacheEntryAddress(uint cacheInfo)
{
    return cacheInfo * 8;
}

void setCacheEntryUint2(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint2 v)
{
    cacheBuffer.Store(byteAddress + 0 * 4, v.x);
    cacheBuffer.Store(byteAddress + 1 * 4, v.y);
}

uint2 getCacheEntryUint2(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    uint2 result;
    result.x = cacheBuffer.Load(byteAddress + 0 * 4);
    result.y = cacheBuffer.Load(byteAddress + 1 * 4);
    return result;
}

// Utility for writing a float4 into a float4 buffer
// Use float4CacheAddress to compute byteAddress
void setCacheEntryFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress, float4 v)
{
    cacheBuffer.Store(byteAddress + 0 * 4, asuint(v.x));
    cacheBuffer.Store(byteAddress + 1 * 4, asuint(v.y));
    cacheBuffer.Store(byteAddress + 2 * 4, asuint(v.z));
    cacheBuffer.Store(byteAddress + 3 * 4, asuint(v.w));
}

// Utility for writing a float2 into a float2 buffer
// Use float2CacheAddress to compute byteAddress
void setCacheEntryFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress, float2 v)
{
    cacheBuffer.Store(byteAddress + 0 * 4, asuint(v.x));
    cacheBuffer.Store(byteAddress + 1 * 4, asuint(v.y));
}

// Utility for writing a float into a float buffer
// Use floatCacheAddress to compute byteAddress
void setCacheEntryFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress, float v)
{
    cacheBuffer.Store(byteAddress + 0 * 4, asuint(v));
}

// Utility for clearing a float4 in a float4 buffer
// Use float4CacheAddress to compute byteAddress
void clearCacheEntryFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    setCacheEntryFloat4(cacheBuffer, byteAddress, float4(0.0, 0.0, 0.0, 0.0));
}

// Utility for clearing a float2 in a float2 buffer
// Use float2CacheAddress to compute byteAddress
void clearCacheEntryFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    setCacheEntryFloat2(cacheBuffer, byteAddress, float2(0.0, 0.0));
}

// Utility for clearing a float in a float buffer
// Use floatCacheAddress to compute byteAddress
void clearCacheEntryFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    setCacheEntryFloat(cacheBuffer, byteAddress, 0.0f);
}

// Utility for writing a specific float4 element of a float4 entry with multiple elements
// Use float4CacheEntryAddress to compute byteAddress
void setCacheElementFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset, float4 value)
{
    setCacheEntryFloat4(cacheBuffer, byteAddress + float4CacheAddress(elementOffset), value);
}

// Utility for writing a specific float2 element of a float2 entry with multiple elements
// Use float2CacheEntryAddress to compute byteAddress
void setCacheElementFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset, float2 value)
{
    setCacheEntryFloat2(cacheBuffer, byteAddress + float2CacheAddress(elementOffset), value);
}

// Utility for writing a specific float element of a float entry with multiple elements
// Use floatCacheEntryAddress to compute byteAddress
void setCacheElementFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset, float value)
{
    setCacheEntryFloat(cacheBuffer, byteAddress + floatCacheAddress(elementOffset), value);
}

// Utility for writing a single float4 value to all elements of a float4 entry
// Use float4CacheEntryAddress to compute byteAddress
void setAllCacheEntryElementsFloat4(RWByteAddressBuffer cacheBuffer,
                                 uint byteAddress,
                                 uint numElementsPerEntry,
                                 float4 value)
{
    for (uint i = 0; i < numElementsPerEntry; i++)
    {
        setCacheElementFloat4(cacheBuffer, byteAddress, i, value);
    }
}

// Utility for writing a single float2 value to all elements of a float2 entry
// Use float2CacheEntryAddress to compute byteAddress
void setAllCacheEntryElementsFloat2(RWByteAddressBuffer cacheBuffer,
                                 uint byteAddress,
                                 uint numElementsPerEntry,
                                 float2 value)
{
    for (uint i = 0; i < numElementsPerEntry; i++)
    {
        setCacheElementFloat2(cacheBuffer, byteAddress, i, value);
    }
}

// Utility for writing a single float value to all elements of a float entry
// Use floatCacheEntryAddress to compute byteAddress
void setAllCacheEntryElementsFloat(RWByteAddressBuffer cacheBuffer,
                                   uint byteAddress,
                                   uint numElementsPerEntry,
                                   float value)
{
    for (uint i = 0; i < numElementsPerEntry; i++)
    {
        setCacheElementFloat(cacheBuffer, byteAddress, i, value);
    }
}

// Utility for clearing a specific float4 element of a float4 entry with multiple elements
// Use float4CacheEntryAddress to compute byteAddress
void clearCacheEntryElementFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    setCacheElementFloat4(cacheBuffer, byteAddress, elementOffset, float4(0.0, 0.0, 0.0, 0.0));
}

// Utility for clearing a specific float2 element of a float2 entry with multiple elements
// Use float2CacheEntryAddress to compute byteAddress
void clearCacheEntryElementFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    setCacheElementFloat2(cacheBuffer, byteAddress, elementOffset, float2(0.0, 0.0));
}

// Utility for clearing a specific float element of a float entry with multiple elements
// Use floatCacheEntryAddress to compute byteAddress
void clearCacheEntryElementFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    setCacheElementFloat(cacheBuffer, byteAddress, elementOffset, 0.0f);
}

// Utility for clearing all elements of a float4 entry with multiple elements
// Use float4CacheEntryAddress to compute byteAddress
void clearAllCacheEntryElementsFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint strideElementsPerEntry)
{
    setAllCacheEntryElementsFloat4(cacheBuffer, byteAddress, strideElementsPerEntry, float4(0.0, 0.0, 0.0, 0.0));
}

// Utility for clearing all elements of a float2 entry with multiple elements
// Use float2CacheEntryAddress to compute byteAddress
void clearAllCacheEntryElementsFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint strideElementsPerEntry)
{
    setAllCacheEntryElementsFloat2(cacheBuffer, byteAddress, strideElementsPerEntry, float2(0.0, 0.0));
}

// Utility for clearing all elements of a float entry with multiple elements
// Use floatCacheEntryAddress to compute byteAddress
void clearAllCacheEntryElementsFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint strideElementsPerEntry)
{
    setAllCacheEntryElementsFloat(cacheBuffer, byteAddress, strideElementsPerEntry, 0.0f);
}

// Utility for reading a float4 from a float4 buffer
// Use float4CacheAddress to compute byteAddress
float4 getCacheEntryFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    float4 entry;
    entry.x = asfloat(cacheBuffer.Load(byteAddress + 0 * 4));
    entry.y = asfloat(cacheBuffer.Load(byteAddress + 1 * 4));
    entry.z = asfloat(cacheBuffer.Load(byteAddress + 2 * 4));
    entry.w = asfloat(cacheBuffer.Load(byteAddress + 3 * 4));
    return entry;
}

uint4 getCacheEntryUint4(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    return cacheBuffer.Load4(byteAddress);
}

uint getCacheEntryUint(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    return cacheBuffer.Load(byteAddress);
}

// Utility for reading a float2 from a float2 buffer
// Use float2CacheAddress to compute byteAddress
float2 getCacheEntryFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    float2 entry;
    entry.x = asfloat(cacheBuffer.Load(byteAddress + 0 * 4));
    entry.y = asfloat(cacheBuffer.Load(byteAddress + 1 * 4));
    return entry;
}

// Utility for reading a float from a float buffer
// Use floatCacheAddress to compute byteAddress
float getCacheEntryFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress)
{
    float entry = asfloat(cacheBuffer.Load(byteAddress + 0 * 4));
    return entry;
}

// Utility for reading a specific float4 element from a float4 entry with multiple elements
// Use float4CacheEntryAddress to compute byteAddress
float4 getCacheEntryElementFloat4(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    return getCacheEntryFloat4(cacheBuffer, byteAddress + float4CacheAddress(elementOffset));
}

uint4 getCacheEntryElementUint4(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    return getCacheEntryUint4(cacheBuffer, byteAddress + float4CacheAddress(elementOffset));
}

uint getCacheEntryElementUint(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    return getCacheEntryUint(cacheBuffer, byteAddress + floatCacheAddress(elementOffset));
}

// Utility for reading a specific float2 element from a float2 entry with multiple elements
// Use float2CacheEntryAddress to compute byteAddress
float2 getCacheEntryElementFloat2(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    return getCacheEntryFloat2(cacheBuffer, byteAddress + float2CacheAddress(elementOffset));
}

// Utility for reading a specific float element from a float entry with multiple elements
// Use floatCacheEntryAddress to compute byteAddress
float getCacheEntryElementFloat(RWByteAddressBuffer cacheBuffer, uint byteAddress, uint elementOffset)
{
    return getCacheEntryFloat(cacheBuffer, byteAddress + floatCacheAddress(elementOffset));
}
