#pragma once
#include "VoxelizationBase.h"
#include "ImageLoader.h"
#include "Profiler.h"
#include <fstream>

class MeshSampler
{
private:
    GridData& gridData;
    ImageLoader& loader;
    Image* currentBaseColor;
    Image* currentSpecular;
    Image* currentNormal;
    float3x3 currentTBN;
    uint voxelCount;

public:
    uint sampleFrequency;
    std::vector<ABSDF> ABSDFBuffer;
    std::vector<Ellipsoid> ellipsoidBuffer;
    std::vector<std::vector<float3>> pointsInVoxels;
    std::string fileName;

    MeshSampler(uint sampleFrequency = 0)
        : gridData(VoxelizationBase::GlobalGridData), loader(ImageLoader::Instance()), sampleFrequency(sampleFrequency)
    {
        voxelCount = gridData.totalVoxelCount();
        currentBaseColor = nullptr;
        currentNormal = nullptr;
        currentSpecular = nullptr;
        fileName = ToString(gridData.voxelCount) + "_" + std::to_string(sampleFrequency) + ".bin";
        ABSDFBuffer.resize(voxelCount);
        ellipsoidBuffer.resize(voxelCount);
        pointsInVoxels.resize(voxelCount);
    }

    void sumPoints()
    {
        for (uint i = 0; i < voxelCount; i++)
        {
            int3 cellInt = IndexToCell(i, gridData.voxelCount);
            Ellipsoid e = VoxelizationUtility::FitEllipsoid(pointsInVoxels[i], cellInt);
            ellipsoidBuffer[i] = e;
        }
    }

    void sampleArea(float3 tri[3], float2 triuv[3], std::vector<float3>& points, int3 cellInt)
    {
        if (points.size() == 0)
            return;
        if (points.size() < 3)
            std::cout << "Less than 3 intersection points in voxel!" << std::endl;

        int index = CellToIndex(cellInt, gridData.voxelCount);
        std::vector<float2> uvs;
        for (uint i = 0; i < points.size(); i++)
        {
            float3 coord = VoxelizationUtility::BarycentricCoordinates(tri[0], tri[1], tri[2], points[i]);
            float2 uv = triuv[0] * coord.x + triuv[1] * coord.y + triuv[2] * coord.z;
            uvs.push_back(uv);
            pointsInVoxels[index].push_back(points[i]);
        }

        float area = VoxelizationUtility::PolygonArea(points);
        float3 baseColor = currentBaseColor->SampleArea(uvs).xyz();
        float4 spec = currentSpecular ? currentSpecular->SampleArea(uvs) : float4(0, 0, 0, 0);
        float3 normal = currentNormal ? currentNormal->SampleArea(uvs).xyz() : float3(0, 0, 1);
        normal = math::normalize(normal);
        normal = VoxelizationUtility::CalcNormal(currentTBN, normal);
        ABSDFInput input = {baseColor, spec, normal, area};
        MaterialUtility::Accumulate(ABSDFBuffer[index], input);
    }

    void calcTriangle(float3 tri[3], float2 triuv[3])
    {
        int xMin, yMin, zMin, xMax, yMax, zMax;
        xMin = yMin = zMin = voxelCount;
        xMax = yMax = zMax = 0;
        for (size_t i = 0; i < 3; i++)
        {
            xMin = std::min(xMin, (int)math::floor(tri[i].x));
            yMin = std::min(yMin, (int)math::floor(tri[i].y));
            zMin = std::min(zMin, (int)math::floor(tri[i].z));
            xMax = std::max(xMax, (int)math::floor(tri[i].x));
            yMax = std::max(yMax, (int)math::floor(tri[i].y));
            zMax = std::max(zMax, (int)math::floor(tri[i].z));
        }
        for (int z = zMin; z <= zMax; z++)
        {
            for (int y = yMin; y <= yMax; y++)
            {
                for (int x = xMin; x <= xMax; x++)
                {
                    int3 cellInt = int3(x, y, z);
                    float3 minPoint = float3(cellInt);
                    std::vector<float3> points = VoxelizationUtility::BoxClip(minPoint, minPoint + 1.f, tri);
                    sampleArea(tri, triuv, points, cellInt);
                }
            }
        }
    }

    void sampleMesh(MeshHeader mesh, float3* pPos, float2* pUV, uint3* pTri)
    {
        currentBaseColor = loader.loadImage(mesh.materialID, BaseColor);
        currentSpecular = loader.loadImage(mesh.materialID, Specular);
        currentNormal = loader.loadImage(mesh.materialID, Normal);
        for (size_t tid = 0; tid < mesh.triangleCount; tid++)
        {
            uint3 triangle = pTri[tid + mesh.triangleOffset];
            float3 tri[3] = {pPos[triangle.x], pPos[triangle.y], pPos[triangle.z]};
            // 世界坐标处理成网格坐标
            for (int i = 0; i < 3; i++)
            {
                tri[i] = (tri[i] - gridData.gridMin) / gridData.voxelSize;
            }
            float2 triuv[3] = {pUV[triangle.x], pUV[triangle.y], pUV[triangle.z]};
            currentTBN = VoxelizationUtility::BuildTBN(tri, triuv);
            calcTriangle(tri, triuv);
        }
    }

    void sampleAll(SceneHeader scene, std::vector<MeshHeader> meshList, float3* pPos, float2* pUV, uint3* pTri)
    {
        Tools::Profiler::BeginSample("Mesh Sampling");
        for (size_t i = 0; i < meshList.size(); i++)
        {
            sampleMesh(meshList[i], pPos, pUV, pTri);
        }
        sumPoints();
        Tools::Profiler::EndSample("Mesh Sampling");
        Tools::Profiler::Print();
        std::cout << "TIME PER VOXEL: " << std::chrono::duration<double>(Tools::Profiler::timeDict["Mesh Sampling"]).count() / voxelCount
                  << " s" << std::endl;
        Tools::Profiler::Reset();
    }

    void write() const
    {
        std::ofstream f;
        std::string s = VoxelizationBase::ResourceFolder + fileName;
        f.open(s, std::ios::binary);

        f.write(reinterpret_cast<char*>(&gridData), sizeof(GridData));
        f.write(reinterpret_cast<const char*>(ABSDFBuffer.data()), (size_t)voxelCount * sizeof(ABSDF));
        f.write(reinterpret_cast<const char*>(ellipsoidBuffer.data()), voxelCount * sizeof(Ellipsoid));

        f.close();
        VoxelizationBase::FileUpdated = true;
    }
};

//    void sampleMaterial(float3 position, float2 uv, int index)
//{
//    float3 baseColor = currentBaseColor->Sample(uv).xyz();
//    float4 spec = currentSpecular ? currentSpecular->Sample(uv) : float4(0, 0, 0, 0);
//    float3 normal = currentNormal ? currentNormal->Sample(uv).xyz() : float3(0, 0, 1);
//    normal = VoxelizationUtility::CalcNormal(currentTBN, normal);
//    ABSDFInput input = {baseColor, spec, normal, 1};
//    MaterialUtility::Accumulate(ABSDFBuffer[index], input);
//    pointsInVoxels[index].push_back(position);
//}
//
// void sampleMaterial(float3 position, float2 uv)
//{
//    int3 p = int3(position);
//    int index = CellToIndex(p, gridData.voxelCount);
//    sampleMaterial(position, uv, index);
//}
//
// void sampleTriangle(float3 tri[3], float2 triuv[3])
//{
//    float3 BC = tri[2] - tri[1];
//    float3 AC = tri[2] - tri[0];
//    float k = length(BC) / length(AC);
//    float S = 0.5f * length(cross(BC, AC));
//    float sampleCount = sampleFrequency * S;
//    float temp = sqrt(2 * sampleCount / k);
//    uint aCount = (uint)ceil(temp);
//    uint bCount = (uint)ceil(temp * k);
//
//    float deltaA = 1.0f / (aCount + 1);
//    float deltaB = 1.0f / (bCount + 1);
//
//    for (float a = deltaA; a < 1; a += deltaA)
//    {
//        for (float b = deltaB; b < 1; b += deltaB)
//        {
//            if (a + b > 1)
//                break;
//            float3 pos = tri[0] * a + tri[1] * b + tri[2] * (1 - a - b);
//            float2 uv = triuv[0] * a + triuv[1] * b + triuv[2] * (1 - a - b);
//            sampleMaterial(pos, uv);
//        }
//    }
//}
