#pragma once
#include "../HostDeviceShared.slang"
#include "Sampling.slang"
#include "SphericalHarmonics.slang"

#if !defined(HOST_CODE)
#include "Random.slang"
#endif

BEGIN_NAMESPACE_FALCOR

//忽略罕见的7/8/9边形情况
#define MAX_VERTEX_COUNT 6
#define MAX_POLYGON_COUNT 16

struct Polygon
{
    float3 vertices[MAX_VERTEX_COUNT];
    uint count;
    float3 normal;

    MUTATING
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
        float s = dot(normalize(cross(v1, v2)), normal);    //如果删掉normalize，会有一定量的点投影面积偏小
        return s >= 1e-6f;      //如果改成0，会有大量的点投影面积偏大
    }

    bool intersectRay(float3 rayOrigin, float3 rayDir)
    {
        float denom = dot(rayDir, normal);
        //if (abs(denom) < epsilon)
        //    return false;
        float t = dot(vertices[0] - rayOrigin, normal) / denom;
        if(t < 0)
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

struct PolygonInVoxel
{
    Polygon polygons[MAX_POLYGON_COUNT];
    float3 cellMin;
    uint count;

    MUTATING
    void init()
    {
        count = 0;
        cellMin = float3(0);
    }

    MUTATING
    void add(Polygon polygon)
    {
        if (count < MAX_POLYGON_COUNT)
        {
            polygons[count] = polygon;
            count++;
        }
    }

    bool intersectRay(float3 rayOrigin, float3 rayDir)
    {
        for (uint i = 0; i < count; i++)
        {
            if (polygons[i].intersectRay(rayOrigin, rayDir))
                return true;
        }
        return false;
    }

#if defined(HOST_CODE)
    void addTo(std::vector<float3> &points)
    {
        for (uint i = 0; i < count; i++)
        {
            polygons[i].addTo(points);
        }
    }
#else
    SphericalHarmonics SampleProjectArea(uint times, inout UniformSampleGenerator sg)
    {
        SphericalHarmonics SH = {};
        SH.init();
        float3 cellCenter = cellMin + 0.5f;
        float weight = 4.f * PI / times / 2;
        for (uint i = 0; i < times; i++)
        {
            float3 direction = sample_sphere(Next2(sg));
            Basis2 basis = orthonormal_basis(direction);
            SamplingRay ray = rayToVoxel(Next2(sg), direction, basis, cellCenter);
            bool hit = false;
            for (uint j = 0; j < count; j++)
            {
                if (polygons[j].intersectRay(ray.origin, ray.direction))
                {
                    hit = true;
                    break;
                }
            }
            if (hit)
            {
                SH.accumulate(direction); 
                SH.accumulate(-direction); // 正反方向的采样结果总是相同
            }
        }
        SH.mul(2.35619449f * weight);   // 一条射线被遮挡，则在这次采样中认为该方向上的投影面积等于外接球的投影面积
        return SH;
    }
#endif
};

END_NAMESPACE_FALCOR
