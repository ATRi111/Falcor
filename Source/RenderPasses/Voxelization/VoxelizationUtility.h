#pragma once
#include "Falcor.h"
#include "Profiler.h"
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

    static void removeRepeatPoints(std::vector<float3>& points)
    {
        std::unordered_set<float3, Float3Hash, Float3Equal> temp(points.begin(), points.end());
        points.assign(temp.begin(), temp.end());
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
    static float PolygonArea(std::vector<float3>& points)
    {
        const size_t n = points.size();
        if (n < 3)
            return 0.0f;

        float3 s = float3(0);
        for (size_t i = 0; i < n; ++i)
        {
            float3 a = points[i];
            float3 b = points[(i + 1) % n];
            float3 c = cross(a, b); // a × b
            s += c;
        }
        return 0.5f * std::sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
    }

    static float PolygonArea(std::vector<float2>& points)
    {
        const size_t n = points.size();
        if (n < 3)
            return 0.0f;
        float area = 0;
        for (size_t i = 0; i < n; ++i)
        {
            float2 a = points[i];
            float2 b = points[(i + 1) % n];
            area += a.x * b.y - a.y * b.x;
        }
        area = 0.5f * abs(area);
        return area;
    }

    static float3x3 BuildTBN(float3 tri[3], float2 triuv[3])
    {
        float3 e1 = tri[1] - tri[0];
        float3 e2 = tri[2] - tri[0];
        float2 duv1 = triuv[1] - triuv[0];
        float2 duv2 = triuv[2] - triuv[0];

        float D = duv1.x * duv2.y - duv1.y * duv2.x;
        float3 N = normalize(cross(e1, e2));

        float3x3 ret;
        if (abs(D) < 1e-8)
        {
            float3 T = normalize(e1 - N * dot(N, e1));
            float3 B = normalize(cross(N, T));
            ret.setCol(0, T);
            ret.setCol(1, B);
            ret.setCol(2, N);
            return ret;
        }

        float r = 1.0 / D;
        float3 Tp = (e1 * duv2.y - e2 * duv1.y) * r;
        float3 Bp = (e2 * duv1.x - e1 * duv2.x) * r;

        float3 T = normalize(Tp - N * dot(N, Tp));
        float3 B = normalize(Bp - N * dot(N, Bp));
        ret.setCol(0, T);
        ret.setCol(1, B);
        ret.setCol(2, N);
        return ret;
    }

    static float3 CalcNormal(float3x3 TBN, float3 normalMapColor)
    {
        float3 normal = normalMapColor * 2.f - 1.f;
        normal = math::normalize(math::mul(TBN, normal));
        return normal;
    }

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
        float bounds[6] = {minPoint.x, maxPoint.x, minPoint.y, maxPoint.y, minPoint.z, maxPoint.z};
        bool greater = true;
        for (uint i = 0; i < 6; i++)
        {
            planeClip(polygon, temp, i >> 1, bounds[i], greater);
            polygon.swap(temp);
            if (polygon.empty())
                return polygon;
            greater = !greater;
        }

        return polygon;
    }

    static Ellipsoid FitEllipsoid(std::vector<float3>& points, int3 cellInt)
    {
        Ellipsoid e;
        float3 sum = float3(0);
        uint n = points.size();
        if (n == 0)
        {
            e.center = float3(0.5f);
            e.B = float3x3::identity();
            e.det = 1;
            return e;
        }

        removeRepeatPoints(points);
        n = points.size();
        for (uint i = 0; i < n; i++)
        {
            sum += points[i];
        }
        e.center = sum / (float)n;
        // 二次方程
        float3x3 cov = float3x3::zeros(); // xx,xy,xz,yx,yy,yz,zx,zy,zz
        for (uint i = 0; i < n; i++)
        {
            float3 v = points[i] - e.center;
            cov[0][0] += v.x * v.x;
            cov[0][1] += v.x * v.y;
            cov[0][2] += v.x * v.z;
            cov[1][0] += v.y * v.x;
            cov[1][1] += v.y * v.y;
            cov[1][2] += v.y * v.z;
            cov[2][0] += v.z * v.x;
            cov[2][1] += v.z * v.y;
            cov[2][2] += v.z * v.z;
        }
        cov = cov * (1.f / n);

        cov = (math::transpose(cov) + cov) * 0.5f;
        // 避免出现奇异矩阵
        float tr = cov[0][0] + cov[1][1] + cov[2][2];
        float lam = 1e-6f * std::max(tr, 1e-6f);
        cov[0][0] += lam;
        cov[1][1] += lam;
        cov[2][2] += lam;

        float3x3 inv = math::inverse(cov);
        float maxDot = 1e-12f;
        for (uint i = 0; i < n; i++)
        {
            float3 v = points[i] - e.center;
            float dot = math::dot(v, mul(inv, v));
            maxDot = std::max(maxDot, dot);
        }
        e.B = inv * (1.0f / maxDot);
        e.det = math::max(math::determinant(e.B), 1e-6f);
        e.center -= float3(cellInt);
        return e;
    }
};
