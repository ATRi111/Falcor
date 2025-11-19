#pragma once
#include "Utils/HostDeviceShared.slangh"

#if defined(HOST_CODE)
#include<vector>
#endif

BEGIN_NAMESPACE_FALCOR

struct Triangle
{
    float3 vertices[3];

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        for (int i = 0; i < 3; i++)
        {
            vertices[i] = float3(0);
        }
    }
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
            return float3(1, 1, 1) / 3;

        float v = (d11 * d20 - d01 * d21) / denom;
        float w = (d00 * d21 - d01 * d20) / denom;
        float u = 1 - v - w;

        return float3(u, v, w);
    }
};

END_NAMESPACE_FALCOR
