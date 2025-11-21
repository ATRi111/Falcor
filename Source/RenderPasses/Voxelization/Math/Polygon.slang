#pragma once
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
    float3 normal;

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        count = 0;
    }

#if defined(HOST_CODE)
    //顶点必须有序,必须至少包含三个点,必须是凸多边形
    void init(std::vector<float3>& points)
    {
        uint n = math::min(MAX_VERTEX_COUNT, (int)points.size());
        count = n;
        for (uint i = 0; i < n; i++)
        {
            vertices[i] = points[i];
        }
        normal = normalize(cross(vertices[1] - vertices[0], vertices[2] - vertices[0]));
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

    bool calcSign(float3 p, float3 n, uint i)
    {
        float3 v1 = vertices[(i + 1) % count] - vertices[i];
        float3 v2 = p - vertices[i];
        float s = dot(cross(v1, v2), n);
        return s >= 0;
    }

    bool intersectRay(float3 rayOrigin, float3 rayDir)
    {
        float denom = dot(rayDir, normal);
        if (denom == 0.0f)
            return false;
        float t = dot(vertices[0] - rayOrigin, normal) / denom;
        if (t < 0.0f)
            return false;
        float3 p = rayOrigin + t * rayDir;
        bool positive = calcSign(p, normal, 0);
        for (uint i = 1; i < count; ++i)
        {
            if (calcSign(p, normal, i) != positive)
                return false; //有正有负说明点在多边形外部
        }

        return true;
    }

    bool sampleVisible(float3 rayOrigin, float3 rayDir)
    {
        float denom = dot(rayDir, normal);
        float t = dot(vertices[0] - rayOrigin, normal) / denom;         // 默认t>0
        float3 p = rayOrigin + t * rayDir;
        bool positive = calcSign(p, normal, 0);
        for (uint i = 1; i < count; ++i)
        {
            if (calcSign(p, normal, i) != positive)
                return true;
        }
        return false;
    }
};

END_NAMESPACE_FALCOR
