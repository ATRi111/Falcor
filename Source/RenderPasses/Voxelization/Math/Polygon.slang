#pragma once
#include "../HostDeviceShared.slang"
#include "Sampling.slang"
#include "SphericalHarmonics.slang"

#if !defined(HOST_CODE)
#include "Random.slang"
#endif

BEGIN_NAMESPACE_FALCOR

// 忽略罕见的7/8/9边形情况
#define MAX_VERTEX_COUNT 6
#define MAX_POLYGON_COUNT 16

struct Polygon
{
    float3 vertices[MAX_VERTEX_COUNT];
    uint count;
    float3 normal;

    MUTATING
    void init() { count = 0; }

#if defined(HOST_CODE)
    // 顶点必须有序,必须至少包含三个点,必须是凸多边形，不能有重合的点
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

    float calcArea()
    {
        float3 s = float3(0);
        for (uint i = 0; i < count; ++i)
        {
            float3 a = vertices[i];
            float3 b = vertices[(i + 1) % count];
            s += cross(a, b);
        }
        return sqrt(dot(s, s)) / 2;
    }

    float calcProjArea(float3 direction)
    {
        return calcArea() * abs(dot(direction, normal));
    }
#if defined(HOST_CODE)
    float3 calcCentroid(float& totalArea) const
#else
    float3 calcCentroid(out float totalArea)
#endif
    {
        // 用顶点0做三角扇分解
        float3 v0 = vertices[0];
        float3 sum = float3(0);
        totalArea = 0;

        for (uint i = 1; i + 1 < count; ++i)
        {
            float3 a = v0;
            float3 b = vertices[i];
            float3 c = vertices[i + 1];

            float3 ab = b - a;
            float3 ac = c - a;
            float3 s = cross(ab, ac);
            float area = sqrt(dot(s, s)) * 0.5f;
            if (area <= 0.0f)
                continue;

            float3 triCenter = (a + b + c) / 3.0f;
            sum += triCenter * area;
            totalArea += area;
        }

        if (totalArea <= 0)
            return v0;

        return sum / totalArea;
    }

    MUTATING
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
        float s = dot(normalize(cross(v1, v2)), normal); // 删掉normalize反而导致更多体素多边形投影面积失真
        return s >= 1e-6f;                               // 如果改成0，会有大量的点投影面积偏大
    }

    float intersectRay(float3 rayOrigin, float3 rayDir)
    {
        float denom = dot(rayDir, normal);
        // if (abs(denom) < epsilon)
        //     return false;
        float t = dot(vertices[0] - rayOrigin, normal) / denom;
        if (t < 0)
            return -1;
        float3 p = rayOrigin + t * rayDir;
        for (uint i = 0; i < count; ++i)
        {
            if (!inside(p, i))
                return -1;
        }
        return t;
    }
};

struct PolygonRange
{
    uint localHead;
    uint count;
    int3 cellInt;

    MUTATING
    void init(int3 c)
    {
        localHead = 0;
        count = 0;
        cellInt = c;
    }

#if !defined(HOST_CODE)
    float3 calcCentroid(StructuredBuffer<Polygon> polygons, out float totalArea)
    {
        float3 sum = float3(0);
        totalArea = 0;

        for (uint i = 0; i < count; ++i)
        {
            float area;
            float3 c = polygons[i + localHead].calcCentroid(area);
            sum += c * area;
            totalArea += area;
        }

        if (totalArea <= 0)
            return cellInt + float3(0.5f);

        return sum / totalArea;
    }

    float calcTotalProjArea(StructuredBuffer<Polygon> polygons, float3 direction)
    {
        float sum = 0;
        for (uint i = 0; i < count; ++i)
        {
            sum += polygons[i + localHead].calcProjArea(direction);
        }
        return sum;
    }
#endif
};

END_NAMESPACE_FALCOR
