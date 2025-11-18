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
        e.center -= float3(cellInt);
        return e;
    }

    static inline float3x3 Outer(const float3 a, const float3 b)
    {
        float3x3 M = float3x3::zeros();
        M[0][0] = a.x * b.x;
        M[0][1] = a.x * b.y;
        M[0][2] = a.x * b.z;
        M[1][0] = a.y * b.x;
        M[1][1] = a.y * b.y;
        M[1][2] = a.y * b.z;
        M[2][0] = a.z * b.x;
        M[2][1] = a.z * b.y;
        M[2][2] = a.z * b.z;
        return M;
    }

    // 最小体积包围椭球（MVEE），共线/共面时使用；否则回退 FitEllipsoid。
    static Ellipsoid FitEllipsoidMVEE(std::vector<float3>& points, int3 cellInt, uint maxIter = 256u, float eps = 1e-5f)
    {
        Ellipsoid e;
        e.center = float3(0.5f);
        e.B = float3x3::identity();

        uint n = (uint)points.size();
        if (n == 0)
            return e;

        removeRepeatPoints(points);
        n = (uint)points.size();
        if (n == 0)
            return e;

        // 基准点与退化检测
        const float3 p0 = points[0];
        int i1 = -1, i2 = -1;
        for (uint i = 1; i < n; ++i)
        {
            float3 d = points[i] - p0;
            if (math::dot(d, d) > 1e-20f)
            {
                i1 = (int)i;
                break;
            }
        }
        if (i1 < 0)
        {
            // 全部重合
            e.center = p0 - float3(cellInt);
            e.B = float3x3::identity();
            return e;
        }
        float3 v1 = points[i1] - p0;
        for (uint j = i1 + 1; j < n; ++j)
        {
            float3 v2 = points[j] - p0;
            float3 c = math::cross(v1, v2);
            if (math::dot(c, c) > 1e-20f)
            {
                i2 = (int)j;
                break;
            }
        }

        // ---------- 共线 ----------
        if (i2 < 0)
        {
            float3 u = math::normalize(v1);
            float tmin = 0.0f, tmax = 0.0f;
            for (uint i = 0; i < n; ++i)
            {
                float t = math::dot(points[i] - p0, u);
                if (i == 0)
                {
                    tmin = tmax = t;
                }
                else
                {
                    if (t < tmin)
                        tmin = t;
                    if (t > tmax)
                        tmax = t;
                }
            }
            float tc = 0.5f * (tmin + tmax);
            float a = fmaxf(1e-6f, 0.5f * (tmax - tmin));      // 主半轴长度
            float thin = fmaxf(1e-6f, 1e-3f * fmaxf(a, 1.0f)); // 正交方向极薄厚度

            float inv_a2 = 1.0f / (a * a);
            float inv_thin = 1.0f / (thin * thin);

            float3x3 uu = Outer(u, u);
            float3x3 I = float3x3::identity();
            e.B = uu * inv_a2 + (I + uu * -1.0f) * inv_thin;

            e.center = p0 + u * tc;
            e.center -= float3(cellInt);
            return e;
        }

        // ---------- 共面（最常见） ----------
        float3 nrm = math::normalize(math::cross(v1, points[i2] - p0));

        // 动态阈值判断共面（尺度相关）
        float avgR = 0.0f;
        for (uint i = 0; i < n; ++i)
            avgR += sqrtf(fmaxf(0.0f, math::dot(points[i] - p0, points[i] - p0)));
        avgR = (n > 0) ? (avgR / (float)n) : 1.0f;
        float planeTol = 1e-4f * (avgR + 1e-3f);

        bool coplanar = true;
        for (uint i = 0; i < n; ++i)
        {
            float d = fabsf(math::dot(points[i] - p0, nrm));
            if (d > planeTol)
            {
                coplanar = false;
                break;
            }
        }

        if (coplanar)
        {
            // 构造平面正交基 {u, v}, 法向 nrm
            float3 u = math::normalize(v1);
            float3 v = math::normalize(math::cross(nrm, u));

            // 2D 坐标（float）
            std::vector<float> xs(n), ys(n);
            for (uint i = 0; i < n; ++i)
            {
                float3 d = points[i] - p0;
                xs[i] = math::dot(d, u);
                ys[i] = math::dot(d, v);
            }

            // Khachiyan (2D) 权重
            const float D = 2.0f;
            std::vector<float> w(n, 1.0f / (float)n);

            for (uint it = 0; it < maxIter; ++it)
            {
                // X = Σ w_k * q_k q_k^T, q_k = [x,y,1]^T
                float3x3 X = float3x3::zeros();
                for (uint k = 0; k < n; ++k)
                {
                    float q0 = xs[k], q1 = ys[k], q2 = 1.0f, wk = w[k];
                    X[0][0] += wk * q0 * q0;
                    X[0][1] += wk * q0 * q1;
                    X[0][2] += wk * q0 * q2;
                    X[1][0] += wk * q1 * q0;
                    X[1][1] += wk * q1 * q1;
                    X[1][2] += wk * q1 * q2;
                    X[2][0] += wk * q2 * q0;
                    X[2][1] += wk * q2 * q1;
                    X[2][2] += wk * q2 * q2;
                }
                // 轻微正则，防奇异
                float reg = 1e-8f;
                X[0][0] += reg;
                X[1][1] += reg;
                X[2][2] += reg;

                float3x3 Xi = math::inverse(X);

                // M_k = q_k^T * X^{-1} * q_k
                uint j = 0;
                float mmax = -1.0f;
                for (uint k = 0; k < n; ++k)
                {
                    float3 q = float3(xs[k], ys[k], 1.0f);
                    float3 t = mul(Xi, q);
                    float Mk = math::dot(q, t);
                    if (Mk > mmax)
                    {
                        mmax = Mk;
                        j = k;
                    }
                }

                float step = (mmax - (D + 1.0f)) / ((D + 1.0f) * (mmax - 1.0f));
                if (step <= eps)
                    break;

                for (uint k = 0; k < n; ++k)
                    w[k] *= (1.0f - step);
                w[j] += step;
            }

            // 中心（2D）
            float cx = 0.0f, cy = 0.0f;
            for (uint k = 0; k < n; ++k)
            {
                cx += w[k] * xs[k];
                cy += w[k] * ys[k];
            }

            // S2 = Σ w_i ([x-c][y-c])([x-c][y-c])^T
            float S00 = 0.0f, S01 = 0.0f, S11 = 0.0f;
            for (uint k = 0; k < n; ++k)
            {
                float dx = xs[k] - cx, dy = ys[k] - cy, wk = w[k];
                S00 += wk * dx * dx;
                S01 += wk * dx * dy;
                S11 += wk * dy * dy;
            }

            // 用 3×3 的块对角矩阵把 2×2 的 S2 嵌入，借助 math::inverse 求 inv(S2)
            float3x3 S3 = float3x3::zeros();
            S3[0][0] = S00;
            S3[0][1] = S01;
            S3[1][0] = S01;
            S3[1][1] = S11;
            S3[2][2] = 1.0f;
            // 轻微正则
            float tr = S3[0][0] + S3[1][1] + S3[2][2];
            float lam = 1e-8f * fmaxf(tr, 1e-6f);
            S3[0][0] += lam;
            S3[1][1] += lam;
            float3x3 S3i = math::inverse(S3);

            // A2 = inv(S2) / D，取 S3i 的左上 2×2
            float A00 = S3i[0][0] * (1.0f / D);
            float A01 = S3i[0][1] * (1.0f / D);
            float A10 = S3i[1][0] * (1.0f / D);
            float A11 = S3i[1][1] * (1.0f / D);

            // 回到 3D：B = U*A2*U^T + alpha*(nrm nrm^T)
            float3x3 uu = Outer(u, u);
            float3x3 vv = Outer(v, v);
            float3x3 uv = Outer(u, v);
            float3x3 vu = Outer(v, u);
            float3x3 Bp = uu * A00 + vv * A11 + uv * A01 + vu * A10;

            // 法向极薄厚度（与平面内尺度相对）
            float aMean = sqrtf(fmaxf(1e-12f, S00 + S11));
            float thin = fmaxf(1e-6f, 1e-3f * aMean);
            float alpha = 1.0f / (thin * thin);
            float3x3 nn = Outer(nrm, nrm);

            e.B = Bp + nn * alpha;
            e.center = p0 + u * cx + v * cy;
            e.center -= float3(cellInt);
            return e;
        }

        // 非共面
        const float D = 3.0f;
        std::vector<float> w(n, 1.0f / (float)n);

        for (uint it = 0; it < maxIter; ++it)
        {
            // X = Σ w_k * q_k q_k^T, q_k = [x, y, z, 1]^T
            float4x4 X = float4x4::zeros();
            for (uint k = 0; k < n; ++k)
            {
                const float3& p = points[k];
                float x = p.x, y = p.y, z = p.z, wk = w[k];

                X[0][0] += wk * x * x;
                X[0][1] += wk * x * y;
                X[0][2] += wk * x * z;
                X[0][3] += wk * x * 1.0f;
                X[1][0] += wk * y * x;
                X[1][1] += wk * y * y;
                X[1][2] += wk * y * z;
                X[1][3] += wk * y * 1.0f;
                X[2][0] += wk * z * x;
                X[2][1] += wk * z * y;
                X[2][2] += wk * z * z;
                X[2][3] += wk * z * 1.0f;
                X[3][0] += wk * 1.0f * x;
                X[3][1] += wk * 1.0f * y;
                X[3][2] += wk * 1.0f * z;
                X[3][3] += wk * 1.0f * 1.0f;
            }
            // 轻微正则
            float reg = 1e-8f;
            X[0][0] += reg;
            X[1][1] += reg;
            X[2][2] += reg;
            X[3][3] += reg;

            float4x4 Xi = math::inverse(X);

            // M_k = q_k^T * X^{-1} * q_k
            uint j = 0;
            float mmax = -1.0f;
            for (uint k = 0; k < n; ++k)
            {
                const float3& p = points[k];
                float4 q = float4(p.x, p.y, p.z, 1.0f);
                float4 t = mul(Xi, q);
                float Mk = q.x * t.x + q.y * t.y + q.z * t.z + q.w * t.w; // 避免依赖是否有 float4 dot 重载
                if (Mk > mmax)
                {
                    mmax = Mk;
                    j = k;
                }
            }

            float step = (mmax - (D + 1.0f)) / ((D + 1.0f) * (mmax - 1.0f)); // D=3 → (mmax-4)/(4*(mmax-1))
            if (step <= eps)
                break;

            for (uint k = 0; k < n; ++k)
                w[k] *= (1.0f - step);
            w[j] += step;
        }

        // 3D 中心
        float3 c = float3(0.0f);
        for (uint k = 0; k < n; ++k)
            c += points[k] * w[k];

        // S = Σ w_i (p_i - c)(p_i - c)^T
        float3x3 S = float3x3::zeros();
        for (uint k = 0; k < n; ++k)
        {
            float3 d = points[k] - c;
            float wk = w[k];
            S[0][0] += wk * d.x * d.x;
            S[0][1] += wk * d.x * d.y;
            S[0][2] += wk * d.x * d.z;
            S[1][0] += wk * d.y * d.x;
            S[1][1] += wk * d.y * d.y;
            S[1][2] += wk * d.y * d.z;
            S[2][0] += wk * d.z * d.x;
            S[2][1] += wk * d.z * d.y;
            S[2][2] += wk * d.z * d.z;
        }
        // 轻微正则避免奇异
        float tr = S[0][0] + S[1][1] + S[2][2];
        float lam = 1e-8f * fmaxf(tr, 1e-6f);
        S[0][0] += lam;
        S[1][1] += lam;
        S[2][2] += lam;

        float3x3 Sinv = math::inverse(S);
        e.B = Sinv * (1.0f / 3.0f); // D=3
        e.center = c;
        e.center -= float3(cellInt);
        return e;
    }
};
