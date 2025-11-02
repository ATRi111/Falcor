#pragma once
#include "Falcor.h"

enum AddressingMode
{
    Wrap,   ///< Wrap around
    Clamp,  ///< Clamp the normalized coordinates to [0, 1]
    Border, ///< If out-of-bound, use the sampler's border color
};

enum FilterMode
{
    Point,
    Linear,
};

class Image
{
public:
    std::string name;
    float4* data;
    uint2 size;
    AddressingMode addressingMode;
    FilterMode filterMode;

    Image(float4* data, uint2 size) : size(size)
    {
        uint bytes = sizeof(float4) * size.x * size.y;
        this->data = reinterpret_cast<float4*>(malloc(bytes));
        memcpy(this->data, data, bytes);
        addressingMode = Wrap;
        filterMode = Linear;
    }

    ~Image() { free(data); }

    float4 GetPixel(uint2 xy)
    {
        uint index = xy.x + xy.y * size.x;
        float4 ret = data[index];
        return ret;
    }

    float4 Sample(float2 uv)
    {
        switch (addressingMode)
        {
        case Wrap:
            uv -= floor(uv);
            break;
        case Clamp:
            uv = math::clamp(uv, float2(0), float2(1 - 1e-5));
            break;
        case Border:
            if (math::any(uv < float2(0)) || math::any(uv >= float2(1)))
                return float4(0);
            break;
        }
        uint2 xy = uint2(floor(uv.x * size.x), floor(uv.y * size.y));
        return GetPixel(xy);
    }
};
