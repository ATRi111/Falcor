#pragma once
#include "Falcor.h"
#include <unordered_set>
using namespace Falcor;

struct Edge
{
    float3 from;
    float3 to;

    float3 lerp(float t) const { return from + t * (to - from); }
    bool collinear(float3 point, float tolerance = 1e-4f) const
    {
        float3 v1 = to - from;
        float3 v2 = point - from;
        float3 cross = math::cross(v1, v2);
        return math::dot(cross, cross) <= tolerance * tolerance * math::dot(v1, v1) * math::dot(v2, v2);
    }
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

    /// <summary>
    /// 判断点是否在三角形内（默认共面）
    /// </summary>
    static bool withinTriangle(float3 points[3], float3 p)
    {
        float3 normal = math::cross(points[1] - points[0], points[2] - points[0]);
        float s0 = math::dot(normal, math::cross(points[0] - p, points[1] - p));
        float s1 = math::dot(normal, math::cross(points[1] - p, points[2] - p));
        float s2 = math::dot(normal, math::cross(points[2] - p, points[0] - p));
        return (s0 >= 0) && (s1 >= 0) && (s2 >= 0);
    }

    static bool approximatelyEqual(float a, float b, float tolerance = 1e-6) { return abs(a - b) <= tolerance; }
    static bool approximatelyEqual(float3 a, float3 b, float tolerance = 1e-6)
    {
        return approximatelyEqual(a.x, b.x, tolerance) && approximatelyEqual(a.y, b.y, tolerance) &&
               approximatelyEqual(a.z, b.z, tolerance);
    }

    static void removeRepeatPoints(std::vector<float3>& points, float tolerance = 1e-6)
    {
        std::vector<float3> temp;
        for (uint i = 0; i < points.size(); i++)
        {
            for (uint j = 0; j < temp.size(); j++)
            {
                if (approximatelyEqual(points[i], temp[j], tolerance))
                    continue;
            }
            temp.push_back(points[i]);
        }
        points.swap(temp);
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
    /// <summary>
    /// 计算重心坐标
    /// </summary>
    static float3 BarycentricCoordinates(float3 A, float3 B, float3 C, float3 P)
    {
        float3 v0 = B - A;
        float3 v1 = C - A;
        float3 v2 = P - A;

        float d00 = dot(v0, v0);
        float d01 = dot(v0, v1);
        float d11 = dot(v1, v1);
        float d20 = dot(v2, v0);
        float d21 = dot(v2, v1);

        float denom = d00 * d11 - d01 * d01;

        if (abs(denom) < 1e-8)
            return float3(1, 1, 1) / 3.f;

        float v = (d11 * d20 - d01 * d21) / denom;
        float w = (d00 * d21 - d01 * d20) / denom;
        float u = 1.0 - v - w;

        return float3(u, v, w);
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
    static std::vector<float3> BoxClip(float3 minPoint, float3 maxPoint, float3 points[3])
    {
        std::vector<float3> polygon;
        std::vector<float3> temp;
        polygon.reserve(12); // 返回结果理论上不超过7个点
        temp.reserve(12);

        // 初始三角形
        polygon.push_back(points[0]);
        polygon.push_back(points[1]);
        polygon.push_back(points[2]);

        // 依次对六个面裁剪
        planeClip(polygon, temp, 0, minPoint.x, true);
        polygon.swap(temp);
        if (polygon.empty())
            return polygon;

        planeClip(polygon, temp, 0, maxPoint.x, false);
        polygon.swap(temp);
        if (polygon.empty())
            return polygon;

        planeClip(polygon, temp, 1, minPoint.y, true);
        polygon.swap(temp);
        if (polygon.empty())
            return polygon;

        planeClip(polygon, temp, 1, maxPoint.y, false);
        polygon.swap(temp);
        if (polygon.empty())
            return polygon;

        planeClip(polygon, temp, 2, minPoint.z, true);
        polygon.swap(temp);
        if (polygon.empty())
            return polygon;

        planeClip(polygon, temp, 2, maxPoint.z, false);
        polygon.swap(temp);

        if (polygon.size() >= 3)
        {
            removeRepeatPoints(polygon);
        }

        return polygon;
    }

    static float polygonArea(const std::vector<float3>& points)
    {
        const size_t n = points.size();
        if (n < 3)
            return 0.f;

        float sx = 0.f, sy = 0.f, sz = 0.f;
        for (size_t i = 0; i < n; ++i)
        {
            float3 a = points[i];
            float3 b = points[(i + 1) % n];
            float3 s = cross(a, b); // a × b
            sx += s.x;
            sy += s.y;
            sz += s.z;
        }
        const float len = std::sqrt(sx * sx + sy * sy + sz * sz);
        return 0.5f * len;
    }
};
