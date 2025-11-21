#pragma once
#include "Falcor.h"
#include "Profiler.h"
#include "Polygon.slang"
#include "SphericalHarmonics.slang"
#include "Sampling.slang"
#include "Triangle.slang"
#include <unordered_set>
#include <tuple>
using namespace Falcor;

struct Float3Hash
{
    size_t operator()(const float3& v) const noexcept
    {
        size_t h1 = std::hash<float>{}(v.x);
        size_t h2 = std::hash<float>{}(v.y);
        size_t h3 = std::hash<float>{}(v.z);
        size_t h = h1;
        h ^= h2 + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
        h ^= h3 + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
        return h;
    }
};
struct Float3Equal
{
    bool operator()(const float3& a, const float3& b) const noexcept { return a.x == b.x && a.y == b.y && a.z == b.z; }
};

class VoxelizationUtility
{
private:
    static float2 intersect(float p1, float p2, float p0, float q)
    {
        float u1 = (p1 - p0) / q;
        float u2 = (p2 - p0) / q;
        if (u1 > u2)
        {
            float temp = u1;
            u1 = u2;
            u2 = temp;
        }
        return float2(u1, u2);
    }

    static bool approximatelyEqual(float a, float b, float tolerance = 1e-6) { return abs(a - b) <= tolerance; }
    static bool approximatelyEqual(float3 a, float3 b, float tolerance = 1e-6)
    {
        return approximatelyEqual(a.x, b.x, tolerance) && approximatelyEqual(a.y, b.y, tolerance) &&
               approximatelyEqual(a.z, b.z, tolerance);
    }

    static float3 intersectAxisPlane(const float3& s, const float3& e, int axis, float planeVal)
    {
        float denom = e[axis] - s[axis];
        if (denom == 0.0)
            return s;
        float t = (planeVal - s[axis]) / denom;
        return math::lerp(s, e, t);
    }

    static void planeClip(const std::vector<float3>& inPoly, std::vector<float3>& outPoly, int axis, float bound, bool greater)
    {
        outPoly.clear();
        if (inPoly.empty())
            return;

        float3 S = inPoly.back();
        bool Sin = greater ? S[axis] >= bound : S[axis] <= bound;

        for (uint i = 0; i < inPoly.size(); ++i)
        {
            const float3 E = inPoly[i];
            const bool Ein = greater ? E[axis] >= bound : E[axis] <= bound;

            if (Ein)
            {
                if (!Sin)
                    outPoly.push_back(intersectAxisPlane(S, E, axis, bound));
                outPoly.push_back(E);
            }
            else
            {
                if (Sin)
                    outPoly.push_back(intersectAxisPlane(S, E, axis, bound));
            }

            S = E;
            Sin = Ein;
        }
    }

public:
    static void RemoveRepeatPoints(std::vector<float3>& points)
    {
        std::unordered_set<float3, Float3Hash, Float3Equal> temp(points.begin(), points.end());
        points.assign(temp.begin(), temp.end());
    }

    /// <summary>
    /// 用轴对齐长方体裁剪有向线段
    /// </summary>
    static float2 BoxClip(float3 minPoint, float3 maxPoint, float3 from, float3 to)
    {
        float uIn = 0, uOut = 1;
        float3 v = to - from;

        float2 u12 = intersect(minPoint.x, maxPoint.x, from.x, v.x);
        uIn = math::max(uIn, u12.x);
        uOut = math::min(uOut, u12.y);
        if (uIn > uOut)
            return float2(-1, -1);

        u12 = intersect(minPoint.y, maxPoint.y, from.y, v.y);
        uIn = math::max(uIn, u12.x);
        uOut = math::min(uOut, u12.y);
        if (uIn > uOut)
            return float2(-1, -1);

        u12 = intersect(minPoint.z, maxPoint.z, from.z, v.z);
        uIn = math::max(uIn, u12.x);
        uOut = math::min(uOut, u12.y);
        if (uIn > uOut)
            return float2(-1, -1);

        return float2(uIn, uOut);
    }

    /// <summary>
    /// 用轴对齐长方体裁剪三角形
    /// </summary>
    static Polygon BoxClipTriangle(float3 minPoint, float3 maxPoint, Triangle tri)
    {
        std::vector<float3> vertices;
        std::vector<float3> temp;
        vertices.reserve(12); // 返回结果理论上不超过9个点
        temp.reserve(12);

        Polygon polygon = {};
        polygon.init();
        // 初始三角形
        tri.addTo(vertices);

        // 依次对六个面裁剪
        float bounds[6] = {minPoint.x, maxPoint.x, minPoint.y, maxPoint.y, minPoint.z, maxPoint.z};
        bool greater = true;
        for (uint i = 0; i < 6; i++)
        {
            planeClip(vertices, temp, i >> 1, bounds[i], greater);
            vertices.swap(temp);
            if (vertices.empty())
                return polygon;
            greater = !greater;
        }

        polygon.init(vertices);
        return polygon;
    }

    static SphericalHarmonics SampleProjectArea(std::vector<Polygon>& polygonsInVoxel,int3 cellInt, uint times)
    {
        SphericalHarmonics SH = {};
        SH.init();
        float3 cellCenter = float3(cellInt) + 0.5f;
        float weight = 4.f * PI / times / 2;
        for (uint i = 0; i < times; i++)
        {
            float3 direction = sample_sphere(VoxelizationBase::Next2());
            Basis2 basis = orthonormal_basis(direction);
            SamplingRay ray = rayToVoxel(VoxelizationBase::Next2(), direction, basis, cellCenter);
            bool hit = false;
            for (size_t j = 0; j < polygonsInVoxel.size(); j++)
            {
                if (!polygonsInVoxel[j].sampleVisible(ray.origin, ray.direction))
                {
                    hit = true;
                    break;
                }
            }
            if (hit)
            {
                SH.accumulate(PROJECT_CIRCLE_AREA, direction, weight); //一条射线被遮挡，则在这次采样中认为该方向上的投影面积等于外接球的投影面积
                SH.accumulate(PROJECT_CIRCLE_AREA, -direction, weight);//正反方向的采样结果总是相同
            }
        }
        return SH;
    }
};
