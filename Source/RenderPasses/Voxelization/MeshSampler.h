#pragma once
#include "VoxelizationBase.h"
#include "Image/ImageLoader.h"
#include "Profiler.h"
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
    std::vector<std::vector<Polygon>> polygonArrays;
    std::vector<PolygonRange> polygonRangeBuffer;
    bool lerpNormal;
    size_t totalPolygonCount;

    MeshSampler() : gridData(VoxelizationBase::GlobalGridData), loader(ImageLoader::Instance())
    {
        currentBaseColor = nullptr;
        currentNormal = nullptr;
        currentSpecular = nullptr;
        lerpNormal = false;
        totalPolygonCount = 0;
    }

    void reset()
    {
        gBuffer.clear();
        vBuffer.clear();
        polygonArrays.clear();
        polygonRangeBuffer.clear();
        totalPolygonCount = 0;
        vBuffer.assign(gridData.totalVoxelCount(), -1);
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
            polygonArrays.emplace_back();
            polygonRangeBuffer.emplace_back();
            polygonRangeBuffer[offset].init(cellInt);
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
        Tools::Profiler::BeginSample("Sample Texture");
        int offset = tryGetOffset(cellInt);

        polygonArrays[offset].push_back(polygon);
        totalPolygonCount++;

        std::vector<float2> uvs;
        for (uint i = 0; i < polygon.count; i++)
        {
            float2 uv = tri.lerpUV(polygon.vertices[i]);
            uvs.push_back(uv);
        }
        float3 baseColor = currentBaseColor ? currentBaseColor->SampleArea(uvs).xyz() : float3(0.5f);
        float4 spec = currentSpecular ? currentSpecular->SampleArea(uvs) : float4(0, 0.5f, 0, 0);

        float3 normal;
        if(lerpNormal)
        {
            float dummy;
            float3 centroid = polygon.calcCentroid(dummy);
            normal = tri.lerpNormal(centroid);
        }
        else
        {
            normal = currentNormal ? currentNormal->SampleArea(uvs).xyz() : float3(0.5f, 0.5f, 1.f);
            normal = calcShadingNormal(tri.TBN, normal);
        }
        if (normal.y < 0)
            normal = -normal;
        float area = polygon.calcArea();
        ABSDFInput input = {baseColor, spec, normal, area };
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
            Polygon polygon = VoxelizationUtility::BoxClipTriangle(minPoint, minPoint + 1.f, tri); // 多边形与三角形顶点顺序一致
            Tools::Profiler::EndSample("Clip");
            polygon.normal = tri.TBN.getCol(2); // 几何法线
            if (polygon.count >= 3)
                sampleArea(tri, polygon, cellInt);
        }
    }

    void sampleMesh(MeshHeader mesh, float3* pPos, float3* pNormal, float2* pUV, uint3* pIndex)
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
            tri.normals[0] = pNormal[indices.x];
            tri.normals[1] = pNormal[indices.y];
            tri.normals[2] = pNormal[indices.z];

            // 世界坐标处理成网格坐标
            for (int i = 0; i < 3; i++)
            {
                tri.vertices[i] = (tri.vertices[i] - gridData.gridMin) / gridData.voxelSize;
            }
            tri.buildTBN();
            clip(tri);
        }
    }

    void sampleAll(SceneHeader scene, std::vector<MeshHeader> meshList, float3* pPos, float3* pNormal, float2* pUV, uint3* pTri)
    {
        for (size_t i = 0; i < meshList.size(); i++)
        {
            sampleMesh(meshList[i], pPos, pNormal, pUV, pTri);
        }
        gridData.solidVoxelCount = gBuffer.size();
    }
};
