#pragma once
#include "../HostDeviceShared.slang"
#include "AABB.slang"

BEGIN_NAMESPACE_FALCOR

inline float3 calcShadingNormal(float3x3 TBN, float3 normalMapColor)
{
    float3 normal = normalMapColor * 2.f - 1.f;
    normal = normalize(mul(TBN, normal));
    return normal;
}

struct Triangle
{
    float3 vertices[3];
    float2 uvs[3];
    float3x3 TBN;

    MUTATING
    void init()
    {
        for (int i = 0; i < 3; i++)
        {
            vertices[i] = float3(0);
            uvs[i] = float2(0);
        }
    }

#if defined(HOST_CODE)
    void addTo(std::vector<float3>& points)
    {
        for (uint i = 0; i < 3; i++)
        {
            points.push_back(vertices[i]);
        }
    }
#endif

    // 判断点是否在三角形内（必须共面）
    bool contains2D(float3 p)
    {
        float3 normal = cross(vertices[1] - vertices[0], vertices[2] - vertices[0]);
        float s0 = dot(normal, cross(vertices[0] - p, vertices[1] - p));
        float s1 = dot(normal, cross(vertices[1] - p, vertices[2] - p));
        float s2 = dot(normal, cross(vertices[2] - p, vertices[0] - p));
        return (s0 >= 0) && (s1 >= 0) && (s2 >= 0);
    }

    float3 barycentricCoordinates(float3 p)
    {
        float3 v0 = vertices[1] - vertices[0];
        float3 v1 = vertices[2] - vertices[0];
        float3 v2 = p - vertices[0];

        float d00 = dot(v0, v0);
        float d01 = dot(v0, v1);
        float d11 = dot(v1, v1);
        float d20 = dot(v2, v0);
        float d21 = dot(v2, v1);

        float denom = d00 * d11 - d01 * d01;

        if (abs(denom) < 1e-8)
            return float3(1) / float3(3);

        float v = (d11 * d20 - d01 * d21) / denom;
        float w = (d00 * d21 - d01 * d20) / denom;
        float u = 1 - v - w;

        return float3(u, v, w);
    }

    float2 lerpUV(float3 p)
    {
        float3 coord = barycentricCoordinates(p);
        return uvs[0] * coord.x + uvs[1] * coord.y + uvs[2] * coord.z;
    }

    AABBInt calcAABBInt()
    {
        AABBInt aabb;
        aabb.init();
        for (int i = 0; i < 3; i++)
        {
            aabb.accumulate((int3)floor(vertices[i]));
        }
        aabb.complete();
        return aabb;
    }

    MUTATING
    void buildTBN()
    {
        float3 e1 = vertices[1] - vertices[0];
        float3 e2 = vertices[2] - vertices[0];
        float2 duv1 = uvs[1] - uvs[0];
        float2 duv2 = uvs[2] - uvs[0];

        float D = duv1.x * duv2.y - duv1.y * duv2.x;
        float3 N = normalize(cross(e1, e2));
        float3 T, B;
        if (abs(D) < 1e-8)
        {
            T = normalize(e1 - N * dot(N, e1));
            B = normalize(cross(N, T));
        }
        else
        {
            float r = 1.0 / D;
            float3 Tp = (e1 * duv2.y - e2 * duv1.y) * r;
            float3 Bp = (e2 * duv1.x - e1 * duv2.x) * r;

            T = normalize(Tp - N * dot(N, Tp));
            B = normalize(Bp - N * dot(N, Bp));
        }

#if defined(HOST_CODE)
        TBN.setCol(0, T);
        TBN.setCol(1, B);
        TBN.setCol(2, N);
#else
        TBN = float3x3(T, B, N);
        TBN = transpose(TBN);
#endif
    }
};

END_NAMESPACE_FALCOR
