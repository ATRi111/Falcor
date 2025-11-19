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
        for (uint i = 0; i < MAX_VERTEX_COUNT; i++)
        {
            vertices[i] = float3(0);
        }
    }

#if defined(HOST_CODE)
    void init(std::vector<float3>& points)
    {
        count = points.size();
        uint n = math::min(MAX_VERTEX_COUNT, (int)points.size());
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
        float3 s = float3(0);
        for (uint i = 0; i < count; ++i)
        {
            float3 a = vertices[i];
            float3 b = vertices[(i + 1) % count];
            s += cross(a, b);
        }
        return sqrt(s.x * s.x + s.y * s.y + s.z * s.z) / 2;
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

    bool intersectRay(float3 rayOrigin, float3 rayDir)
    {
        float3 v0 = vertices[0];
        float3 n = cross(vertices[1] - v0, vertices[2] - v0);

        float denom = dot(rayDir, n);
        if (denom == 0.0f)
            return false;
        float t = dot(v0 - rayOrigin, n) / denom;
        if (t < 0.0f)
            return false;

        float3 P = rayOrigin + t * rayDir;

        // 必须是凸多边形
        bool positive = false, negative = false;
        for (uint i = 0; i < count; ++i)
        {
            float3 a = vertices[i];
            float3 b = vertices[(i + 1) % count];
            float3 e = b - a;
            float3 c = P - a;
            float s = dot(cross(e, c), n);
            if (s > 0.0f)
                positive = true;
            else if (s < 0.0f)
                negative = true;

            if (positive && negative)
                return false; //有正有负说明点在多边形外部
        }

        return true;
    }
};

END_NAMESPACE_FALCOR
