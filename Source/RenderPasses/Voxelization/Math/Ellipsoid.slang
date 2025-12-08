#pragma once
#include "../HostDeviceShared.slang"
#include "Projection.slang"
#include "Polygon.slang"
#if !defined(HOST_CODE)
import Utils.Math.MathHelpers;
#endif

#define MAX_FIT_POINT_COUNT 100

BEGIN_NAMESPACE_FALCOR

struct Ellipse
{
    float2x2 M; // 默认中心位于原点,y^TMy <=1

    float area() { return PI / sqrt(determinant(M)); }

#if !defined(HOST_CODE)
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
#endif
};

struct Ellipsoid
{
    float3 center; // 相对于所在体素左下角的偏移量（涉及求交运算时，以椭球的中心为原点）
    float3x3 B;    // x^T B x <=1

#if defined(HOST_CODE)
    void fit(const PolygonInVoxel& piv)
#else
    [mutating]
    void fit(PolygonInVoxel piv)
#endif
    {
        float3 sum = float3(0);
        int n = 0;
        float totalArea = 0.0f;

        center = piv.calcCentroid(totalArea);

        float3x3 cov = zeros(); // xx,xy,xz,yx,yy,yz,zx,zy,zz
         for (uint pi = 0; pi < piv.count; ++pi)
        {
             Polygon poly = piv.polygons[pi];
             for (uint i = 0; i < poly.count; ++i)
             {
                 float3 v = poly.vertices[i] - center;
                 cov[0][0] += v.x * v.x;
                 cov[0][1] += v.x * v.y;
                 cov[0][2] += v.x * v.z;
                 cov[1][0] += v.y * v.x;
                 cov[1][1] += v.y * v.y;
                 cov[1][2] += v.y * v.z;
                 cov[2][0] += v.z * v.x;
                 cov[2][1] += v.z * v.y;
                 cov[2][2] += v.z * v.z;
                 n++;
             }
         }
         cov = cov * (1.f / n);

        //float3x3 M2 = zeros();
        //for (uint pi = 0; pi < piv.count; ++pi)
        //{
        //    Polygon poly = piv.polygons[pi];
        //    float3 v0 = poly.vertices[0];
        //    for (uint i = 1; i + 1 < poly.count; ++i)
        //    {
        //        float3 a = v0;
        //        float3 b = poly.vertices[i];
        //        float3 c = poly.vertices[i + 1];

        //        float3 ab = b - a;
        //        float3 ac = c - a;
        //        float3 s = cross(ab, ac);
        //        float area = sqrt(dot(s, s)) * 0.5f;
        //        if (area <= 0.0f)
        //            continue;

        //        // 对三角形 T(a,b,c) 有解析公式：
        //        // ∫_T x x^T dA = area / 12 * ( (a+b+c)(a+b+c)^T + (aa^T + bb^T + cc^T) )
        //        float3 S1 = a + b + c;

        //        float ax = a.x, ay = a.y, az = a.z;
        //        float bx = b.x, by = b.y, bz = b.z;
        //        float cx = c.x, cy = c.y, cz = c.z;

        //        float sx = S1.x, sy = S1.y, sz = S1.z;

        //        float w = area / 12.0f;

        //        // M2 += w * (S1*S1^T + a*a^T + b*b^T + c*c^T)，逐元素写出来
        //        M2[0][0] += w * (sx * sx + ax * ax + bx * bx + cx * cx);
        //        M2[0][1] += w * (sx * sy + ax * ay + bx * by + cx * cy);
        //        M2[0][2] += w * (sx * sz + ax * az + bx * bz + cx * cz);

        //        M2[1][0] += w * (sy * sx + ay * ax + by * bx + cy * cx);
        //        M2[1][1] += w * (sy * sy + ay * ay + by * by + cy * cy);
        //        M2[1][2] += w * (sy * sz + ay * az + by * bz + cy * cz);

        //        M2[2][0] += w * (sz * sx + az * ax + bz * bx + cz * cx);
        //        M2[2][1] += w * (sz * sy + az * ay + bz * by + cz * cy);
        //        M2[2][2] += w * (sz * sz + az * az + bz * bz + cz * cz);
        //    }
        //}


        //// 3. 得到协方差：cov = E[x x^T] - μ μ^T
        //float invArea = 1.0f / totalArea;
        //float3x3 cov = M2 * invArea;
        //cov = sub(cov, mulT(center, center));

        cov = (transpose(cov) + cov) * 0.5f;
        // 避免出现奇异矩阵
        float tr = cov[0][0] + cov[1][1] + cov[2][2];
        float lam = 1e-6f * max(tr, 1e-6f);
        cov[0][0] += lam;
        cov[1][1] += lam;
        cov[2][2] += lam;

        float3x3 inv = inverse(cov);
        float maxDot = 1e-12f;
        for (uint pi = 0; pi < piv.count; ++pi)
        {
            Polygon poly = piv.polygons[pi];
            for (uint i = 0; i < poly.count; ++i)
            {
                float3 v = poly.vertices[i] - center;
                float temp = dot(v, mul(inv, v));
                maxDot = max(maxDot, temp);
            }
        }
        B = inv * (1.0f / maxDot);
        center -= piv.cellMin;
    }

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

    bool contains(float3 p, float epsilon)
    {
        float3 offset = p - center;
        float d = dot(offset, mul(B, offset));
        return d <= (1.0 + epsilon) * (1.0 + epsilon);
    }
#if !defined(HOST_CODE)
    Ellipse project(float3 v, Basis2 basis)
    {
        float3 u = basis.u, w = basis.w;

        float3 Bu = mul(B, u), Bv = mul(B, v), Bw = mul(B, w);
        float2x2 A2 = make2x2(dot(u, Bu), dot(u, Bw), dot(w, Bu), dot(w, Bw));
        float2 b2 = float2(dot(u, Bv), dot(w, Bv));
        float2x2 B2 = mulT(b2, b2);
        float b = dot(v, Bv);

        float2x2 M = A2 - B2 / b;

        Ellipse e;
        e.M = M;
        return e;
    }

    float projectArea(float3 v)
    {
        Basis2 basis = orthonormal_basis(v);
        Ellipse ee = project(v, basis);
        return ee.area();
    }
#endif
};

END_NAMESPACE_FALCOR
