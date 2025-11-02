#pragma once
#include "VoxelizationBase.h"
#include "ImageLoader.h"
#include <fstream>

class MeshSampler
{
private:
    GridData& gridData;
    Image* currentBaseColor;

public:
    ImageLoader loader;
    uint sampleFrequency;
    float4* diffuseBuffer;
    std::string fileName;

    MeshSampler(uint sampleFrequency) : gridData(VoxelizationBase::GlobalGridData), sampleFrequency(sampleFrequency)
    {
        currentBaseColor = nullptr;
        fileName = ToString(gridData.voxelCount) + "_" + std::to_string(sampleFrequency) + ".bin";
        diffuseBuffer = reinterpret_cast<float4*>(malloc(gridData.totalVoxelCount() * sizeof(float4)));
        for (size_t i = 0; i < gridData.totalVoxelCount(); i++)
        {
            diffuseBuffer[i] = float4(0);
        }
    }

    ~MeshSampler() { free(diffuseBuffer); }

    void sampleMaterial(float3 position, float2 texCoord, float2 dduv)
    {
        int3 p = int3(position);
        int index = CellToIndex(p, gridData.voxelCount);
        float4 baseColor = currentBaseColor->Sample(texCoord);
        diffuseBuffer[index] = float4(baseColor.xyz(), 1);
    }

    void sampleTriangle(float3 positions[3], float2 texCoords[3])
    {
        float3 BC = positions[2] - positions[1];
        float3 AC = positions[2] - positions[0];
        float k = length(BC) / length(AC);
        float S = 0.5f * length(cross(BC, AC));
        float sampleCount = sampleFrequency * S;
        float temp = sqrt(2 * sampleCount / k);
        uint aCount = (uint)ceil(temp);
        uint bCount = (uint)ceil(temp * k);

        float deltaA = 1.0f / (aCount + 1);
        float deltaB = 1.0f / (bCount + 1);
        float2 deltaUV = abs(texCoords[0] * deltaA + texCoords[1] * deltaB + texCoords[2] * (-deltaA - deltaB));

        for (float a = deltaA; a < 1; a += deltaA)
        {
            for (float b = deltaB; b < 1; b += deltaB)
            {
                if (a + b > 1)
                    break;
                float3 pos = positions[0] * a + positions[1] * b + positions[2] * (1 - a - b);
                float2 texCoord = frac(texCoords[0] * a + texCoords[1] * b + texCoords[2] * (1 - a - b));
                sampleMaterial(pos, texCoord, deltaUV);
            }
        }
    }

    void sampleMesh(MeshHeader mesh, float3* pPos, float2* pUV, uint3* pTri)
    {
        currentBaseColor = loader.loadImage(mesh.materialID, BaseColor);
        for (size_t tid = 0; tid < mesh.triangleCount; tid++)
        {
            uint3 triangle = pTri[tid + mesh.triangleOffset];
            float3 positions[3] = {pPos[triangle.x], pPos[triangle.y], pPos[triangle.z]};
            // 世界坐标处理成网格坐标
            for (int i = 0; i < 3; i++)
            {
                positions[i] = (positions[i] - gridData.gridMin) / gridData.voxelSize;
            }
            float2 texCoords[3] = {pUV[triangle.x], pUV[triangle.y], pUV[triangle.z]};
            sampleTriangle(positions, texCoords);
        }
    }

    void sampleAll(SceneHeader scene, std::vector<MeshHeader> meshList, float3* pPos, float2* pUV, uint3* pTri)
    {
        for (size_t i = 0; i < meshList.size(); i++)
        {
            sampleMesh(meshList[i], pPos, pUV, pTri);
        }
    }

    void write()
    {
        std::ofstream f;
        std::string s = VoxelizationBase::ResourceFolder + fileName;
        f.open(s, std::ios::binary);

        f.write(reinterpret_cast<char*>(&gridData), sizeof(GridData));
        f.write(reinterpret_cast<char*>(diffuseBuffer), gridData.totalVoxelCount() * sizeof(float4));

        f.close();
        VoxelizationBase::FileUpdated = true;
    }
};
