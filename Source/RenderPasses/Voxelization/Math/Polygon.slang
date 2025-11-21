#pragma once
#include "ConvexHull.slang"
#include "Utils/HostDeviceShared.slangh"

#if defined(HOST_CODE)
#include<vector>
#endif

BEGIN_NAMESPACE_FALCOR

#define MAX_VERTEX_COUNT 12

struct Polygon
{
    float3 vertices[MAX_VERTEX_COUNT];
    uint count;

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        count = 0;
    }

#if defined(HOST_CODE)
    //顶点必须有序
    void init(std::vector<float3>& points)
    {
        uint n = math::min(MAX_VERTEX_COUNT, (int)points.size());
        count = n;
        for (uint i = 0; i < n; i++)
        {
            vertices[i] = points[i];
        }
    }

    void addTo(std::vector<float3>& points)
    {
        for (uint i = 0; i < count; i++)
        {
            points.push_back(vertices[i]);
        }
    }
#endif

    float area()
    {
        // 必须至少包含三个点
        float3 s = float3(0);
        for (uint i = 0; i < count; ++i)
        {
            float3 a = vertices[i];
            float3 b = vertices[(i + 1) % count];
            s += cross(a, b);
        }
        return sqrt(dot(s,s)) / 2;
    }

#if !defined(HOST_CODE)
    [mutating]
#endif
    void add(float3 point)
    {
        if (count < MAX_VERTEX_COUNT)
        {
            vertices[count] = point;
            count++;
        }
    }

    float3 calcNormal()
    {
        // 必须至少包含三个点
        return cross(vertices[1] - vertices[0], vertices[2] - vertices[0]);
    }

    bool calcSign(float3 p, float3 n, uint i)
    {
        float3 v1 = vertices[(i + 1) % count] - vertices[i];
        float3 v2 = p - vertices[i];
        float s = dot(cross(v1, v2), n);
        return s >= 0;
    }

    bool intersectRay(float3 rayOrigin, float3 rayDir)
    {
        // 必须至少包含三个点
        float3 v0 = vertices[0];
        float3 n = cross(vertices[1] - v0, vertices[2] - v0);

        float denom = dot(rayDir, n);
        if (denom == 0.0f)
            return false;
        float t = dot(v0 - rayOrigin, n) / denom;
        if (t < 0.0f)
            return false;

        float3 p = rayOrigin + t * rayDir;

        // 必须是凸多边形
        bool positive = calcSign(p, n, 0);
        for (uint i = 1; i < count; ++i)
        {
            if (calcSign(p, n, i) != positive)
                return false; //有正有负说明点在多边形外部
        }

        return true;
    }

    float sampleVisibility(float3 rayOrigin, float3 rayDir, float3 n, float denom)
    {
        // 默认t>0
        float t = dot(vertices[0] - rayOrigin, n) / denom;
        float3 p = rayOrigin + t * rayDir;
        bool positive = calcSign(p, n, 0);
        for (uint i = 1; i < count; ++i)
        {
            if (calcSign(p, n, i) != positive)
                return 1;
        }
        return 0;
    }
};

END_NAMESPACE_FALCOR
