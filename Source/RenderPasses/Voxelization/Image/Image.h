#pragma once
#include "Falcor.h"
using namespace Falcor;

enum AddressingMode
{
    Wrap,   ///< Wrap around
    Clamp,  ///< Clamp the normalized coordinates to [0, 1]
    Border, ///< If out-of-bound, use the sampler's border color
};

enum FilterMode
{
    Point,
    Bilinear,
};

enum FilterFunction
{
    Average,
    Normalize,
};

struct MipLevel
{
    static float4 NormalizeColor(const float4& c)
    {
        float3 normal = c.xyz() * 2.f - 1.f;
        normal = math::normalize(normal);
        return float4(normal * 0.5f + 0.5f, 1.0f);
    }

    std::vector<float4> pixels;
    uint2 size;
    FilterFunction filterFunction;

    MipLevel(uint2 size, FilterFunction filterFunction) : pixels(size.x * size.y), size(size), filterFunction(filterFunction) {}

    float4 Filter(const std::vector<float4>& v) const
    {
        float4 result = float4(0);
        for (const float4& c : v)
        {
            result += c;
        }
        result /= (float)v.size();
        if (filterFunction == Normalize)
            result = MipLevel::NormalizeColor(result);
        return result;
    }

    void GenerateMipLevel(const std::vector<float4>& higherLevel)
    {
        for (uint y = 0; y < size.y; y++)
        {
            for (uint x = 0; x < size.x; x++)
            {
                uint2 uv0 = uint2(x * 2, y * 2);
                uint2 uv1 = uint2(x * 2 + 1, y * 2);
                uint2 uv2 = uint2(x * 2, y * 2 + 1);
                uint2 uv3 = uint2(x * 2 + 1, y * 2 + 1);
                float4 c0 = higherLevel[uv0.x + uv0.y * size.x * 2];
                float4 c1 = higherLevel[uv1.x + uv1.y * size.x * 2];
                float4 c2 = higherLevel[uv2.x + uv2.y * size.x * 2];
                float4 c3 = higherLevel[uv3.x + uv3.y * size.x * 2];
                pixels[x + y * size.x] = Filter({c0, c1, c2, c3});
            }
        }
    }

    size_t bytes() const { return sizeof(float4) * (size_t)size.x * size.y; }
};

class Image
{
public:
    static float PolygonArea(std::vector<float2>& points)
    {
        const size_t n = points.size();
        if (n < 3)
            return 0.0f;
        float area = 0;
        for (size_t i = 0; i < n; ++i)
        {
            float2 a = points[i];
            float2 b = points[(i + 1) % n];
            area += a.x * b.y - a.y * b.x;
        }
        area = 0.5f * abs(area);
        return area;
    }

    std::string name;
    std::vector<MipLevel> mipLevels;
    AddressingMode addressingMode;
    FilterMode filterMode;
    FilterFunction filterFunction;
    float4 borderColor;

    uint2 size() const { return mipLevels[0].size; }

    Image(float4* data, uint2 size, FilterFunction filterFunction) : filterFunction(filterFunction), borderColor(float4(0))
    {
        uint2 mipSize = size;
        while (mipSize.x > 0 && mipSize.y > 0)
        {
            mipLevels.emplace_back(mipSize, filterFunction);
            // 不考虑纹理大小不是2的整数次幂的情况
            mipSize.x >>= 1;
            mipSize.y >>= 1;
        }
        memcpy(mipLevels[0].pixels.data(), data, mipLevels[0].bytes());
        for (uint i = 1; i < mipLevels.size(); i++)
        {
            mipLevels[i].GenerateMipLevel(mipLevels[i - 1].pixels);
        }
        addressingMode = Wrap;
        filterMode = Bilinear;
    }

    float4 GetPixel(int x, int y, int mipLevel = 0) const
    {
        const MipLevel& mip = mipLevels[mipLevel];
        int index = x + y * mip.size.x;
        float4 ret = mip.pixels[index];
        return ret;
    }

    float4 SamplePoint(float2 uv, int mipLevel = 0) const
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
                return borderColor;
            break;
        }
        uint2 size = mipLevels[mipLevel].size;
        return GetPixel(floor(uv.x * size.x), floor(uv.y * size.y), mipLevel);
    }

    float4 SampleLinear(float2 uv, int mipLevel = 0) const
    {
        uint2 size = mipLevels[mipLevel].size;
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

        float4 c00 = SamplePoint(uv, mipLevel);
        float4 c01 = SamplePoint(uv + float2(du, 0), mipLevel);
        float4 c10 = SamplePoint(uv + float2(0, dv), mipLevel);
        float4 c11 = SamplePoint(uv + float2(du, dv), mipLevel);
        float4 result = c00 * w00 + c01 * w01 + c10 * w10 + c11 * w11;
        if (filterFunction == Normalize)
            result = MipLevel::NormalizeColor(result);
        return result;
    }

    float4 SampleTrilinear(float2 uv, float mipLevel) const
    {
        mipLevel = math::clamp(mipLevel, 0.0f, mipLevels.size() - 1 - (float)1e-6);
        int mip0 = (int)math::floor(mipLevel);
        int mip1 = mip0 + 1;
        float w1 = mipLevel - mip0;
        float w0 = 1.0f - w1;
        float4 c0 = Sample(uv, mip0);
        float4 c1 = Sample(uv, mip1);
        float4 result = c0 * w0 + c1 * w1;
        if (filterFunction == Normalize)
            result = MipLevel::NormalizeColor(result);
        return result;
    }

    float4 Sample(float2 uv, int mipLevel = 0) const
    {
        switch (filterMode)
        {
        case Point:
            return SamplePoint(uv, mipLevel);
        case Bilinear:
            return SampleLinear(uv, mipLevel);
        }
        return borderColor;
    }

    float4 SampleArea(std::vector<float2>& uvs) const
    {
        switch (uvs.size())
        {
        case 0:
            return borderColor;
        case 1:
            return Sample(uvs[0]);
        case 2:
            return Sample(0.5f * (uvs[0] + uvs[1]));
        default:
            float2 center = float2(0);
            for (uint i = 0; i < uvs.size(); i++)
            {
                center += uvs[i];
            }
            center /= (float)uvs.size();
            float area = PolygonArea(uvs);
            area *= mipLevels[0].size.x * mipLevels[0].size.y;
            float lod = 0.5f * math::log2(area);
            return SampleTrilinear(center, lod);
        }
    }
};
