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
    float area;

#if !defined(HOST_CODE)
    [mutating]
#endif
    void init()
    {
        count = 0;
    }

#if defined(HOST_CODE)
    //顶点必须有序,必须至少包含三个点,必须是凸多边形，不能有重合的点
    void init(std::vector<float3>& points)
    {
        uint n = math::min(MAX_VERTEX_COUNT, (int)points.size());
        count = n;
        for (uint i = 0; i < n; i++)
        {
            vertices[i] = points[i];
        }
        area = calcArea();
    }

    void addTo(std::vector<float3>& points)
    {
        for (uint i = 0; i < count; i++)
        {
            points.push_back(vertices[i]);
        }
    }
#endif

    float calcArea()
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

    bool inside(float3 p, uint i)
    {
        float3 v1 = vertices[(i + 1) % count] - vertices[i];
        float3 v2 = p - vertices[i];
        float s = dot(normalize(cross(v1, v2)), normal);
        return s >= 1e-6f;      //不论顺时针还是逆时针，大于0总表示在v1的内侧
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
        for (uint i = 0; i < count; ++i)
        {
            if (!inside(p, i))
                return false;
        }

        return true;
    }

    bool sampleRay(float3 rayOrigin, float3 rayDir)
    {
        float denom = dot(rayDir, normal);
        //if (abs(denom) < epsilon)
        //    return false;
        float t = dot(vertices[0] - rayOrigin, normal) / denom;
        if( t < 0)
            return false;
        float3 p = rayOrigin + t * rayDir;
        for (uint i = 0; i < count; ++i)
        {
             if (!inside(p, i))
                 return false;
        }
        return true;
    }
};

END_NAMESPACE_FALCOR
