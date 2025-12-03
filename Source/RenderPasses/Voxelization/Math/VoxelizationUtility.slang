#pragma once
#include "Polygon.slang"
#include "Triangle.slang"

#define MAX_VERTEX_COUNT_PROCESSING 12

inline float3x3 rotateMatrix(float cosAngle, float3 axis)
{
    float c = cosAngle;
    float s = sqrt(1 - cosAngle * cosAngle);    //默认角度小于180°

    float3 temp = (1 - c) * axis;

    float3x3 rotate;
    rotate[0][0] = c + temp[0] * axis[0];
    rotate[0][1] = temp[1] * axis[0] - s * axis[2];
    rotate[0][2] = temp[2] * axis[0] + s * axis[1];

    rotate[1][0] = temp[0] * axis[1] + s * axis[2];
    rotate[1][1] = c + temp[1] * axis[1];
    rotate[1][2] = temp[2] * axis[1] - s * axis[0];

    rotate[2][0] = temp[0] * axis[2] - s * axis[1];
    rotate[2][1] = temp[1] * axis[2] + s * axis[0];
    rotate[2][2] = c + temp[2] * axis[2];

    return rotate;
}

inline float3x3 rotateMatrix(float3 from, float3 to)
{
    float3 f = normalize(from);
    float3 t = normalize(to);

    float cosAngle = dot(f, t);
    float3 axis = cross(f, t);
    float s = length(axis);

    if (s < 1e-6f)  //几乎共线
    {
        if (cosAngle > 0.0f)
        {
            return float3x3(1.0f, 0, 0, 0, 1.0f, 0, 0, 0, 1.0f);
        }
        else
        {
            float3 ortho = (abs(f.x) < 0.9f) ? float3(1, 0, 0) : float3(0, 1, 0);
            float3 axis180 = normalize(cross(f, ortho));
            return rotateMatrix(-1.0f, axis180);
        }
    }

    axis /= s;
    return rotateMatrix(cosAngle, axis);
}


inline float3 intersectAxisPlane(float3 S, float3 E, int axis, float bound)
{
    float s = S[axis];
    float e = E[axis];
    float t = (bound - s) / (e - s);
    return lerp(S, E, t);
}

inline uint removeAdjacentRepeatPoints(inout float3 v[MAX_VERTEX_COUNT_PROCESSING], uint count)
{
    if (count == 0)
        return 0;

    uint writeIndex = 0;
    for (uint i = 0; i < count; ++i)
    {
        uint next = (i + 1) % count;

        if (all(v[i] == v[next]))
            continue;

        v[writeIndex++] = v[i];
    }
    return writeIndex;
}

inline uint planeClip(float3 inPoly[MAX_VERTEX_COUNT_PROCESSING], uint inCount, out float3 outPoly[MAX_VERTEX_COUNT_PROCESSING], int axis, float bound, bool greater)
{
    uint outCount = 0;

    if (inCount == 0)
        return 0;

    float3 S = inPoly[inCount - 1];
    bool Sin = greater ? (S[axis] >= bound) : (S[axis] <= bound);

    for (uint i = 0; i < inCount; ++i)
    {
        float3 E = inPoly[i];
        bool Ein = greater ? (E[axis] >= bound) : (E[axis] <= bound);

        if (Ein)
        {
            if (!Sin && outCount < MAX_VERTEX_COUNT_PROCESSING)
            {
                outPoly[outCount++] = intersectAxisPlane(S, E, axis, bound);
            }
            if (outCount < MAX_VERTEX_COUNT_PROCESSING)
            {
                outPoly[outCount++] = E;
            }
        }
        else
        {
            if (Sin && outCount < MAX_VERTEX_COUNT_PROCESSING)
            {
                outPoly[outCount++] = intersectAxisPlane(S, E, axis, bound);
            }
        }

        S = E;
        Sin = Ein;
    }

    return outCount;
}

// 用轴对齐包围盒裁剪三角形
inline Polygon boxClipTriangle(float3 minPoint, float3 maxPoint, Triangle tri)
{
    Polygon poly;
    poly.count = 0;

    float3 vertices[MAX_VERTEX_COUNT_PROCESSING];
    float3 temp[MAX_VERTEX_COUNT_PROCESSING];

    uint vCount = 3;
    vertices[0] = tri.vertices[0];
    vertices[1] = tri.vertices[1];
    vertices[2] = tri.vertices[2];

    // 六个平面
    float bounds[6] =
    {
        minPoint.x, maxPoint.x,
        minPoint.y, maxPoint.y,
        minPoint.z, maxPoint.z
    };

    bool greater = true;

    for (uint i = 0; i < 6; ++i)
    {
        uint newCount = planeClip(vertices, vCount, temp, (int)(i >> 1), bounds[i], greater);

        if (newCount == 0)
        {
            poly.count = 0;
            return poly;
        }

        // 把 temp 拷回 vertices
        vCount = newCount;
        for (uint k = 0; k < vCount; ++k)
        {
            vertices[k] = temp[k];
        }

        greater = !greater;
    }

    if (vCount > 3)
    {
        vCount = removeAdjacentRepeatPoints(vertices, vCount);
    }

    for (uint i = 0; i < vCount; ++i)
    {
        poly.add(vertices[i]);
    }
    return poly;
}
