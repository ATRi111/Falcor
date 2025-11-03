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

    float4 GetPixel(int x, int y) const
    {
        int index = x + y * size.x;
        float4 ret = data[index];
        return ret;
    }

    float4 SamplePoint(float2 uv) const
    {
        switch (addressingMode)
        {
        case Wrap:
            uv = math::frac(uv);
            break;
        case Clamp:
            uv = math::clamp(uv, float2(0), float2(1 - 1e-6));
            break;
        case Border:
            if (math::any(uv < float2(0)) || math::any(uv >= float2(1)))
                return float4(0);
            break;
        }
        return GetPixel(floor(uv.x * size.x), floor(uv.y * size.y));
    }

    float4 Sample(float2 uv) const
    {
        switch (filterMode)
        {
        case Point:
            return SamplePoint(uv);
        case Linear:
            float2 xyf = uv * float2(size);
            float2 center = floor(uv * float2(size)) + 0.5f;
            float du = math::sign(xyf.x - center.x) / size.x;
            float dv = math::sign(xyf.y - center.y) / size.y;

            float2 w1 = math::abs(xyf - center);
            float2 w0 = 1.0f - w1;
            float w00, w01, w10, w11;
            w00 = w0.x * w0.y;
            w01 = w1.x * w0.y;
            w10 = w0.x * w1.y;
            w11 = w1.x * w1.y;

            float4 c00 = SamplePoint(uv);
            float4 c01 = SamplePoint(uv + float2(du, 0));
            float4 c10 = SamplePoint(uv + float2(0, dv));
            float4 c11 = SamplePoint(uv + float2(du, dv));
            return c00 * w00 + c01 * w01 + c10 * w10 + c11 * w11;
        }
        return float4(0);
    }
};
