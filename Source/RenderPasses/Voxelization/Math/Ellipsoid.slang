#pragma once
#include "Utils/HostDeviceShared.slangh"
#include "Projection.slang"
#include "ConvexHull.slang"

BEGIN_NAMESPACE_FALCOR

#if !defined(HOST_CODE)

struct Circle
{
    float r; // 默认圆心位于原点

    float area() { return PI * r * r; }

    bool contains(float2 p, float epsilon) { return dot(p, p) <= (r + epsilon) * (r + epsilon); }

    float sectorArea(float2 a, float2 b)
    {
        float ang = atan2(cross2(a, b), dot(a, b));
        return 0.5f * r * r * ang; // 有向面积
    }

    float2 clip(float2 from, float2 to)
    {
        float2 v = to - from;
        float a = dot(v, v);
        float b = 2.0f * dot(from, v);
        float c = dot(from, from) - r * r;
        float d = b * b - 4 * a * c;
        if (d < 0)
            return float2(-1, -1);
        float uIn = 0, uOut = 1;
        float s = sqrt(d);
        uIn = max(uIn, (-b - s) / 2 / a);
        uOut = min(uOut, (-b + s) / 2 / a);
        if (uIn > uOut)
            return float2(-1, -1);
        return float2(uIn, uOut);
    }

    // 圆心与两点连成的三角形和圆相交部分的面积
    float edgeIntersectionArea(float2 from, float2 to)
    {
        float2 v = to - from;
        if (dot(v, v) < 1e-6f)
            return 0.0f;
        float2 inOut = clip(from, to);

        // 无交点
        if (inOut.x < 0.0f && inOut.y < 0.0f)
        {
            if (contains(from, 0) && contains(to, 0)) // 两点均在圆内
                return 0.5f * cross2(from, to);
            return sectorArea(from, to); // 两点均在圆外
        }

        float2 enter = from + v * inOut.x;
        float2 exit = from + v * inOut.y;

        float area = 0.0f;

        if (inOut.x > 0.0f)
            area += sectorArea(from, enter);

        area += 0.5f * cross2(enter, exit);

        if (inOut.y < 1.0f)
            area += sectorArea(exit, to);

        return area; // 有向面积
    }

    float intersectArea(float2 points[CUBE_VERTEX_COUNT])
    {
        float2 hull[CUBE_VERTEX_COUNT];
        int count = convexHull2D(points, 8, hull);
        if (count < 3)
            return 0.0f;

        float acc = 0.0f;
        for (int i = 0; i < count; ++i)
        {
            float2 from = hull[i];
            float2 to = hull[(i + 1) % count];
            acc += edgeIntersectionArea(from, to);
        }

        return abs(acc);
    }
};

struct Ellipse
{
    float2x2 M; // 默认中心位于原点,y^TMy <=1

    float area() { return PI / sqrt(determinant(M)); }

    // M=LL^T→(L^Ty)^T(L^Ty) <= 1
    float2x2 transformToUnitCircle()
    {
        float a = M[0][0];
        float c = M[0][1];
        float b = M[1][1];

        float l00 = sqrt(a);
        float l10 = c / l00;
        float t = b - l10 * l10;
        t = max(t, 1e-12f);
        float l11 = sqrt(t);

        return float2x2(l00, l10, 0.0f, l11);
    }
};
#endif

struct Ellipsoid
{
    float3 center; // 相对于所在体素左下角的偏移量（涉及求交运算时，以椭球的中心为原点）
    float3x3 B;    // x^T B x <=1

#if defined(HOST_CODE)
    void fit(std::vector<float3> &points, int3 cellInt)
    {
        float3 sum = float3(0);
        uint n = points.size();
        if (n == 0)
        {
            center = float3(0.5f);
            B = float3x3::identity();
            return;
        }

        for (uint i = 0; i < n; i++)
        {
            sum += points[i];
        }
        center = sum / (float)n;
        // 二次方程
        float3x3 cov = float3x3::zeros(); // xx,xy,xz,yx,yy,yz,zx,zy,zz
        for (uint i = 0; i < n; i++)
        {
            float3 v = points[i] - center;
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
            float3 v = points[i] - center;
            float dot = math::dot(v, mul(inv, v));
            maxDot = std::max(maxDot, dot);
        }
        B = inv * (1.0f / maxDot);
        center -= float3(cellInt);
    }
#endif

#if !defined(HOST_CODE)
    float2 clip(float3 from, float3 to)
    {
        float3 v = to - from;
        from -= center;
        // 解二次方程
        float a = dot(v, mul(B, v));
        float b = 2.f * dot(v, mul(B, from));
        float c = dot(from, mul(B, from)) - 1.f;
        float d = b * b - 4 * a * c;
        if (d < 0)
            return float2(-1, -1);
        float uIn = 0, uOut = 1;
        float s = sqrt(d);

        uIn = max(uIn, (-b - s) / 2 / a);
        uOut = min(uOut, (-b + s) / 2 / a);
        if (uIn > uOut)
            return float2(-1, -1);
        return float2(uIn, uOut);
    }

    Ellipse project(float3 v, Basis2 basis)
    {
        float3 u = basis.u, w = basis.w;

        float3 Bu = mul(B, u), Bv = mul(B, v), Bw = mul(B, w);
        float2x2 A2 = float2x2(dot(u, Bu), dot(u, Bw), dot(w, Bu), dot(w, Bw));
        float2 b2 = float2(dot(u, Bv), dot(w, Bv));
        float2x2 B2 = mulT(b2, b2);
        float b = dot(v, Bv);

        float2x2 M = A2 - B2 / b;

        Ellipse e;
        e.M = M;
        return e;
    }

    bool contains(float3 p, float epsilon)
    {
        float3 offset = p - center;
        float d = dot(offset, mul(B, offset));
        return d <= (1.0 + epsilon) * (1.0 + epsilon);
    }

    float projectArea(float3 v)
    {
        Basis2 basis = orthonormal_basis(v);
        Ellipse ee = project(v, basis);
        return ee.area();
    }

    // 椭球与所在体素相交的部分的投影面积
    float clippedProjectArea(float3 v)
    {
        static float3 vertices[8] = {
            float3(0, 0, 0),
            float3(0, 0, 1),
            float3(0, 1, 0),
            float3(0, 1, 1),
            float3(1, 0, 0),
            float3(1, 0, 1),
            float3(1, 1, 0),
            float3(1, 1, 1),
        };
        float2 projection[8];
        Basis2 basis = orthonormal_basis(v);
        Ellipse ee = project(v, basis);
        float2x2 LT = ee.transformToUnitCircle();
        Circle circle;
        circle.r = 1;

        for (int i = 0; i < 8; i++)
        {
            float3 temp = vertices[i] - center;
            projection[i] = float2(dot(basis.u, temp), dot(basis.w, temp));
            projection[i] = mul(LT, projection[i]);
        }
        float3 voxelCenter = 0.5f - center;
        float k = circle.intersectArea(projection) / circle.area(); // 同时在椭圆和多边形内的点，占椭圆内所有点的比例
        float area = k * ee.area();
        return area;
    }
#endif
};

END_NAMESPACE_FALCOR
