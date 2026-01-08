#pragma once
#include "../HostDeviceShared.slang"
#include "Projection.slang"
#include "Polygon.slang"
#if !defined(HOST_CODE)
import Utils.Math.MathHelpers;
#endif

BEGIN_NAMESPACE_FALCOR

#if !defined(HOST_CODE)

float3x3 identity3()
{
    return float3x3(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
    );
}

float3x3 diag3(float3 d)
{
    return float3x3(
        d.x, 0, 0,
        0, d.y, 0,
        0, 0, d.z
    );
}

void swapf(inout float a, inout float b)
{
    float t = a; a = b; b = t;
}

void swapCols(inout float3x3 M, int a, int b)
{
    // swap column a and b (remember: indexing is [row][col])
    for (int r = 0; r < 3; ++r)
    {
        float t = M[r][a];
        M[r][a] = M[r][b];
        M[r][b] = t;
    }
}

// One Jacobi rotation to annihilate A[p][q] (A is symmetric)
void jacobiRotateSym3(inout float3x3 A, inout float3x3 V, int p, int q)
{
    float apq = A[p][q];
    if (abs(apq) < 1e-10f) return;

    float app = A[p][p];
    float aqq = A[q][q];

    // Stable t/c/s computation.
    // tau = (aqq - app) / (2*apq)
    float tau = (aqq - app) / (2.0f * apq);

    // handle tau == 0 correctly (t should be 1)
    float t;
    if (tau >= 0.0f)
        t = 1.0f / (tau + sqrt(1.0f + tau * tau));
    else
        t = -1.0f / (-tau + sqrt(1.0f + tau * tau));

    float c = rsqrt(1.0f + t * t);
    float s = t * c;

    // Update A's off-diagonal entries in rows/cols p,q
    for (int k = 0; k < 3; ++k)
    {
        if (k == p || k == q) continue;

        float akp = A[k][p];
        float akq = A[k][q];

        float newAkp = c * akp - s * akq;
        float newAkq = s * akp + c * akq;

        // Keep symmetry
        A[k][p] = newAkp; A[p][k] = newAkp;
        A[k][q] = newAkq; A[q][k] = newAkq;
    }

    // Update diagonal terms (and zero the target)
    float newApp = c * c * app - 2.0f * s * c * apq + s * s * aqq;
    float newAqq = s * s * app + 2.0f * s * c * apq + c * c * aqq;

    A[p][p] = newApp;
    A[q][q] = newAqq;
    A[p][q] = 0.0f;
    A[q][p] = 0.0f;

    // Update eigenvector matrix: V = V * J  (rotate columns p,q)
    // Since we store eigenvectors in columns, right-multiplication is correct.
    for (int i = 0; i < 3; ++i)
    {
        float vip = V[i][p];
        float viq = V[i][q];

        float newVip = c * vip - s * viq;
        float newViq = s * vip + c * viq;

        V[i][p] = newVip;
        V[i][q] = newViq;
    }
}

// Eigen decomposition for symmetric 3x3.
// Returns R (columns are eigenvectors), eval (eigenvalues).
void eigenSym3_Jacobi(float3x3 A, out float3x3 R, out float3 eval)
{
    // Force symmetry just in case
    A = 0.5f * (A + transpose(A));

    R = identity3();

    // Fixed sweeps: enough for 3x3 in practice
    for (int sweep = 0; sweep < 8; ++sweep)
    {
        jacobiRotateSym3(A, R, 0, 1);
        jacobiRotateSym3(A, R, 0, 2);
        jacobiRotateSym3(A, R, 1, 2);
    }

    eval = float3(A[0][0], A[1][1], A[2][2]);

    // Sort descending by eigenvalue (cov should be >=0)
    if (eval.x < eval.y) { swapf(eval.x, eval.y); swapCols(R, 0, 1); }
    if (eval.x < eval.z) { swapf(eval.x, eval.z); swapCols(R, 0, 2); }
    if (eval.y < eval.z) { swapf(eval.y, eval.z); swapCols(R, 1, 2); }

    // Optional: re-orthonormalize a bit (usually not needed for 3x3)
    // You can skip for performance.
}
#endif

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

#if !defined(HOST_CODE)
    [mutating]
    void fit(StructuredBuffer<Polygon> polygons, PolygonRange range)
    {
        float3 sum = float3(0);
        float totalArea = 0.0f;

        center = range.calcCentroid(polygons, totalArea);
        if (totalArea <= 0.0f)
        {
            B = zeros();
            center = float3(0);
            return;
        }

        float3x3 cov = zeros(); // xx,xy,xz,yx,yy,yz,zx,zy,zz

        for (size_t pi = 0; pi < range.count; ++pi)
        {
            Polygon poly = polygons[pi + range.localHead];

            float3 v0 = poly.vertices[0];
            for (uint i = 1; i + 1 < poly.count; ++i)
            {
                float3 a = v0;
                float3 b = poly.vertices[i];
                float3 c = poly.vertices[i + 1];

                float3 ab = b - a;
                float3 ac = c - a;
                float3 s = cross(ab, ac);
                float area = sqrt(dot(s, s)) * 0.5f;
                if (area <= 0)
                    continue;

                // 在局部坐标系下计算
                float3 a0 = a - center;
                float3 b0 = b - center;
                float3 c0 = c - center;

                // 对三角形 T(a0,b0,c0) 有解析公式：
                // ∫_T y y^T dA = area / 12 * ( (a0+b0+c0)(a0+b0+c0)^T + a0 a0^T + b0 b0^T + c0 c0^T )
                float3 S1 = a0 + b0 + c0;

                float ax = a0.x, ay = a0.y, az = a0.z;
                float bx = b0.x, by = b0.y, bz = b0.z;
                float cx = c0.x, cy = c0.y, cz = c0.z;

                float sx = S1.x, sy = S1.y, sz = S1.z;

                float w = area / 12.0f;

                // cov += w * (S1*S1^T + a0*a0^T + b0*b0^T + c0*c0^T)
                cov[0][0] += w * (sx * sx + ax * ax + bx * bx + cx * cx);
                cov[0][1] += w * (sx * sy + ax * ay + bx * by + cx * cy);
                cov[0][2] += w * (sx * sz + ax * az + bx * bz + cx * cz);

                cov[1][0] += w * (sy * sx + ay * ax + by * bx + cy * cx);
                cov[1][1] += w * (sy * sy + ay * ay + by * by + cy * cy);
                cov[1][2] += w * (sy * sz + ay * az + by * bz + cy * cz);

                cov[2][0] += w * (sz * sx + az * ax + bz * bx + cz * cx);
                cov[2][1] += w * (sz * sy + az * ay + bz * by + cz * cy);
                cov[2][2] += w * (sz * sz + az * az + bz * bz + cz * cz);
            }
        }

        cov = cov * (1.0f / totalArea);

        //cov = (transpose(cov) + cov) * 0.5f;
        //// 避免出现奇异矩阵
        //float tr = cov[0][0] + cov[1][1] + cov[2][2];
        //float lam = 1e-6f * max(tr, 1e-6f);
        //cov[0][0] += lam;
        //cov[1][1] += lam;
        //cov[2][2] += lam;

        //float3x3 inv = inverse(cov);
        //float maxDot = 1e-12f;
        //for (size_t pi = 0; pi < range.count; ++pi)
        //{
        //    Polygon poly = polygons[pi + range.localHead];
        //    for (uint i = 0; i < poly.count; ++i)
        //    {
        //        float3 v = poly.vertices[i] - center;
        //        float temp = dot(v, mul(inv, v));
        //        maxDot = max(maxDot, temp);
        //    }
        //}
        //B = inv * (1.0f / maxDot);
        //center -= range.cellInt;

        float3 center0 = center;

        // cov 已经对称化过的话可以略；否则做一次
        cov = 0.5f * (cov + transpose(cov));

        // 更推荐：用“与体素尺度相关”的正则，而不是 1e-6*trace 的固定写法
        // 但先沿用你原逻辑，至少保证可逆
        float tr = cov[0][0] + cov[1][1] + cov[2][2];
        float lam = 1e-6f * max(tr, 1e-6f);
        cov[0][0] += lam;
        cov[1][1] += lam;
        cov[2][2] += lam;

        // 1) PCA：拿主轴方向
        float3x3 R;
        float3 eval;
        eigenSym3_Jacobi(cov, R, eval);

        // 2) 扫所有顶点：在主轴坐标系里求 min/max
        float3 qMin = float3(1e30f, 1e30f, 1e30f);
        float3 qMax = float3(-1e30f, -1e30f, -1e30f);

        for (size_t pi = 0; pi < range.count; ++pi)
        {
            Polygon poly = polygons[pi + range.localHead];
            for (uint i = 0; i < poly.count; ++i)
            {
                float3 p = poly.vertices[i] - center0;
                float3 q = mul(transpose(R), p); // project to PCA axes

                qMin = min(qMin, q);
                qMax = max(qMax, q);
            }
        }

        // 3) 用 OBB 的中心/半长来设置椭球中心与半轴（先不做整体缩放）
        float3 shift = 0.5f * (qMin + qMax);
        float3 half = 0.5f * (qMax - qMin);

        // 建议把椭球中心移到投影区间中心（这一步非常关键，会明显“变紧”）
        center = center0 + mul(R, shift);

        // 4) 防退化：给最小半轴（尤其薄片的“厚度”）
        // 这个参数非常影响“挡光率稀释”：越大越容易漏光；越小数值越紧但可能抖。
        float minHalf = 1e-3f; // 如果体素边长=1，从 1e-3~5e-3 试起
        half = max(half, float3(minHalf, minHalf, minHalf));

        // 5) 再扫一遍算 maxS，做一次整体缩放保证所有点都在椭球内
        float3 invHalf2 = 1.0f / (half * half);
        float maxS = 1e-12f;

        for (size_t pi = 0; pi < range.count; ++pi)
        {
            Polygon poly = polygons[pi + range.localHead];
            for (uint i = 0; i < poly.count; ++i)
            {
                float3 p = poly.vertices[i] - center;
                float3 q = mul(transpose(R), p);

                float s = q.x * q.x * invHalf2.x + q.y * q.y * invHalf2.y + q.z * q.z * invHalf2.z;
                maxS = max(maxS, s);
            }
        }

        // 6) 构造 B：x^T B x <= 1
        float3 invR2 = invHalf2 / maxS; // 等价于把半轴乘 sqrt(maxS)
        B = mul(R, mul(diag3(invR2), transpose(R)));
        B = 0.5f * (B + transpose(B)); // 数值上强制对称

        // 7) 保持你原来的“center 相对体素左下角偏移”的约定
        center -= range.cellInt;
    }
#endif

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
