#pragma once
#include "VoxelizationBase.h"
#include "Image/ImageLoader.h"
#include "Profiler.h"
#include "QuickHull/QuickHull.hpp"
#include "Math/Polygon.slang"
#include "Math/Triangle.slang"
#include "Math/SphericalHarmonics.slang"
#include <unordered_map>

using namespace Falcor;

class MeshSampler
{
private:
    GridData& gridData;
    ImageLoader& loader;
    Image* currentBaseColor;
    Image* currentSpecular;
    Image* currentNormal;
public:
    std::vector<VoxelData> gBuffer;
    std::vector<int> vBuffer;
    std::vector<PolygonInVoxel> polygonBuffer;

    MeshSampler()
        : gridData(VoxelizationBase::GlobalGridData), loader(ImageLoader::Instance())
    {
        currentBaseColor = nullptr;
        currentNormal = nullptr;
        currentSpecular = nullptr;
    }

    void reset()
    {
        clear();
        vBuffer.assign(gridData.totalVoxelCount(), -1);
    }

    void clear()
    {
        gBuffer.clear();
        vBuffer.clear();
        polygonBuffer.clear();
    }

    int tryGetOffset(int3 cellInt)
    {
        int index = CellToIndex(cellInt, gridData.voxelCount);
        if (vBuffer[index] == -1)
        {
            int offset = gBuffer.size();
            vBuffer[index] = offset;
            gBuffer.emplace_back();
            gBuffer[offset].init();
            polygonBuffer.emplace_back();
            polygonBuffer[offset].init();
            polygonBuffer[offset].cellMin = float3(cellInt);
        }
        return vBuffer[index];
    }

    int getOffset(int3 cellInt)
    {
        int index = CellToIndex(cellInt, gridData.voxelCount);
        return vBuffer[index];
    }

    void sampleArea(Triangle& tri, Polygon& polygon, int3 cellInt)
    {
        if (polygon.count < 3)
            return;

        Tools::Profiler::BeginSample("Sample Texture");
        int offset = tryGetOffset(cellInt);

        polygonBuffer[offset].add(polygon);

        std::vector<float2> uvs;
        for (uint i = 0; i < polygon.count; i++)
        {
            float2 uv = tri.lerpUV(polygon.vertices[i]);
            uvs.push_back(uv);
        }

        float3 baseColor = currentBaseColor ? currentBaseColor->SampleArea(uvs).xyz() : float3(0.5f);
        float4 spec = currentSpecular ? currentSpecular->SampleArea(uvs) : float4(0, 0, 0, 0);
        float3 normal = currentNormal ? currentNormal->SampleArea(uvs).xyz() : float3(0.5f, 0.5f, 1.f);
        normal = calcShadingNormal(tri.TBN, normal);
        if (normal.y < 0)
            normal = -normal;
        ABSDFInput input = {baseColor, spec, normal, polygon.calcArea()};
        gBuffer[offset].ABSDF.accumulate(input);

        Tools::Profiler::EndSample("Sample Texture");
    }

    void clip(Triangle& tri)
    {
        AABBInt aabb = tri.calcAABBInt();
        for (int i = 0; i < aabb.count(); i++)
        {
            Tools::Profiler::BeginSample("Clip");
            int3 cellInt = aabb.indexToCell(i);
            float3 minPoint = float3(cellInt);
            Polygon polygon = VoxelizationUtility::BoxClipTriangle(minPoint, minPoint + 1.f, tri);  //多边形与三角形顶点顺序一致
            Tools::Profiler::EndSample("Clip");
            polygon.normal = tri.TBN.getCol(2);  //几何法线
            if (polygon.count >= 3)
                sampleArea(tri, polygon, cellInt);
        }
    }

    void sampleMesh(MeshHeader mesh, float3* pPos, float2* pUV, uint3* pIndex)
    {
        currentBaseColor = loader.loadImage(mesh.materialID, BaseColor);
        currentSpecular = loader.loadImage(mesh.materialID, Specular);
        currentNormal = loader.loadImage(mesh.materialID, Normal);
        for (size_t tid = 0; tid < mesh.triangleCount; tid++)
        {
            Triangle tri = {};
            uint3 indices = pIndex[tid + mesh.triangleOffset];
            tri.vertices[0] = pPos[indices.x];
            tri.vertices[1] = pPos[indices.y];
            tri.vertices[2] = pPos[indices.z];
            tri.uvs[0] = pUV[indices.x];
            tri.uvs[1] = pUV[indices.y];
            tri.uvs[2] = pUV[indices.z];

            // 世界坐标处理成网格坐标
            for (int i = 0; i < 3; i++)
            {
                tri.vertices[i] = (tri.vertices[i] - gridData.gridMin) / gridData.voxelSize;
            }
            tri.buildTBN();
            clip(tri);
        }
    }

    void sampleAll(SceneHeader scene, std::vector<MeshHeader> meshList, float3* pPos, float2* pUV, uint3* pTri)
    {
        for (size_t i = 0; i < meshList.size(); i++)
        {
            sampleMesh(meshList[i], pPos, pUV, pTri);
        }
        gridData.solidVoxelCount = gBuffer.size();
    }

    void analyzeAll()
    {
        using namespace quickhull;
        std::vector<float3> points;
        for (uint i = 0; i < gBuffer.size(); i++)
        {
            Tools::Profiler::BeginSample("Fit Ellipsoid");
            points.clear();
            polygonBuffer[i].addTo(points);
            QuickHull<float> qh;
            ConvexHull<float> hull = qh.getConvexHull(reinterpret_cast<float*>(points.data()), points.size(), true, false, 1e-6f);
            VertexDataSource<float> vertexBuffer = hull.getVertexBuffer();
            points.clear();
            for (uint j = 0; j < vertexBuffer.size(); j++)
            {
                Vector3<float> p = vertexBuffer[j];
                points.emplace_back(p.x, p.y, p.z);
            };
            VoxelizationUtility::RemoveRepeatPoints(points);
            gBuffer[i].ellipsoid.fit(points, polygonBuffer[i].cellMin);
            Tools::Profiler::EndSample("Fit Ellipsoid");

            gBuffer[i].ABSDF.normalizeSelf();
        }
    }
};
