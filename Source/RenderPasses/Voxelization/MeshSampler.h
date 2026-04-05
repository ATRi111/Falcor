#pragma once
#include "VoxelizationBase.h"
#include "Image/ImageLoader.h"
#include "Profiler.h"
#include "Math/Polygon.slang"
#include "Math/Triangle.slang"
#include "Math/SphericalHarmonics.slang"
#include <unordered_map>

using namespace Falcor;

class PolygonGenerator
{
private:
    GridData& gridData;

public:
    std::vector<VoxelData> gBuffer;
    std::vector<int> vBuffer;
    std::vector<std::vector<Polygon>> polygonArrays;
    std::vector<PolygonRange> polygonRangeBuffer;

    PolygonGenerator() : gridData(VoxelizationBase::GlobalGridData)
    {
    }

    void reset()
    {
        gBuffer.clear();
        vBuffer.clear();
        polygonArrays.clear();
        polygonRangeBuffer.clear();
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

    void clip(const InstanceHeader& instance, uint triangleID, Triangle& tri)
    {
        AABBInt aabb = tri.calcAABBInt();
        for (int i = 0; i < aabb.count(); i++)
        {
            int3 cellInt = aabb.indexToCell(i);
            float3 minPoint = float3(cellInt);
            Polygon polygon = VoxelizationUtility::BoxClipTriangle(minPoint, minPoint + 1.f, tri); // Preserve winding from the source triangle.
            polygon.normal = tri.TBN.getCol(2); // Geometric normal.
            if (polygon.count >= 3)
            {
                //sampleArea(tri, polygon, cellInt);
                polygon.triRef.meshID = instance.meshID;
                polygon.triRef.triangleID = triangleID;
                polygon.triRef.materialID = instance.materialID;
                polygon.triRef.instanceID = instance.instanceID;
                int offset = tryGetOffset(cellInt);
                polygonArrays[offset].push_back(polygon);
            }
        }
    }

    void clipMesh(const InstanceHeader& instance, float3* pPos, float3* pNormal, float2* pUV, uint3* pIndex)
    {
        for (uint tid = 0; tid < instance.triangleCount; tid++)
        {
            Triangle tri = {};
            uint3 indices = pIndex[tid + instance.triangleOffset];
            tri.vertices[0] = math::transformPoint(instance.worldMatrix, pPos[indices.x]);
            tri.vertices[1] = math::transformPoint(instance.worldMatrix, pPos[indices.y]);
            tri.vertices[2] = math::transformPoint(instance.worldMatrix, pPos[indices.z]);
            tri.uvs[0] = pUV[indices.x];
            tri.uvs[1] = pUV[indices.y];
            tri.uvs[2] = pUV[indices.z];
            tri.normals[0] = math::normalize(math::transformVector(instance.worldInvTransposeMatrix, pNormal[indices.x]));
            tri.normals[1] = math::normalize(math::transformVector(instance.worldInvTransposeMatrix, pNormal[indices.y]));
            tri.normals[2] = math::normalize(math::transformVector(instance.worldInvTransposeMatrix, pNormal[indices.z]));

            // Convert world-space vertices into grid-space coordinates.
            for (int i = 0; i < 3; i++)
            {
                tri.vertices[i] = (tri.vertices[i] - gridData.gridMin) / gridData.voxelSize;
            }
            tri.buildTBN();
            clip(instance, tid, tri);
        }
    }

    void clipAll(SceneHeader scene, const std::vector<InstanceHeader>& instanceList, float3* pPos, float3* pNormal, float2* pUV, uint3* pTri)
    {
        for (size_t i = 0; i < instanceList.size(); i++)
        {
            clipMesh(instanceList[i], pPos, pNormal, pUV, pTri);
        }
        gridData.solidVoxelCount = gBuffer.size();
    }
};
