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
    uint voxelCount;

public:
    uint sampleFrequency;
    float4* diffuseBuffer;
    float4* specularBuffer;
    Ellipsoid* ellipsoids;
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
        diffuseBuffer = reinterpret_cast<float4*>(malloc(voxelCount * sizeof(float4)));
        specularBuffer = reinterpret_cast<float4*>(malloc(voxelCount * sizeof(float4)));
        ellipsoids = reinterpret_cast<Ellipsoid*>(malloc(voxelCount * sizeof(Ellipsoid)));
        pointsInVoxels.resize(voxelCount);
        for (uint i = 0; i < voxelCount; i++)
        {
            diffuseBuffer[i] = float4(0);
            specularBuffer[i] = float4(0);
        }
    }

    ~MeshSampler()
    {
        free(diffuseBuffer);
        free(specularBuffer);
        free(ellipsoids);
    }

    Ellipsoid fitEllipsoid(std::vector<float3>& points, int3 cellInt)
    {
        Ellipsoid e;
        float3 sum = float3(0);
        uint n = points.size();
        if (n == 0)
        {
            e.center = float3(0.5f);
            e.shape = float3x3::identity();
            return e;
        }

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
        e.shape = inv * (1.0f / maxDot);
        e.center -= float3(cellInt);
        return e;
    }

    void sumPoints()
    {
        for (uint i = 0; i < voxelCount; i++)
        {
            int3 cellInt = IndexToCell(i, gridData.voxelCount);
            Ellipsoid e = fitEllipsoid(pointsInVoxels[i], cellInt);
            ellipsoids[i] = e;
        }
    }

    void sampleMaterial(float3 position, float2 uv, int index)
    {
        float3 baseColor = currentBaseColor->Sample(uv).xyz();
        float4 spec;
        if (currentSpecular)
            spec = currentSpecular->Sample(uv);
        else
            spec = float4(0, 0, 0, 0);
        ABSDFInput input = {baseColor, spec};
        ABSDF absdf = MaterialUtility::CalcABSDF(input);
        diffuseBuffer[index] += absdf.diffuse;
        specularBuffer[index] += absdf.specular;
        pointsInVoxels[index].push_back(position);
    }

    void sampleMaterial(float3 position, float2 uv)
    {
        int3 p = int3(position);
        int index = CellToIndex(p, gridData.voxelCount);
        sampleMaterial(position, uv, index);
    }

    void sampleTriangle(float3 tri[3], float2 triuv[3])
    {
        float3 BC = tri[2] - tri[1];
        float3 AC = tri[2] - tri[0];
        float k = length(BC) / length(AC);
        float S = 0.5f * length(cross(BC, AC));
        float sampleCount = sampleFrequency * S;
        float temp = sqrt(2 * sampleCount / k);
        uint aCount = (uint)ceil(temp);
        uint bCount = (uint)ceil(temp * k);

        float deltaA = 1.0f / (aCount + 1);
        float deltaB = 1.0f / (bCount + 1);

        for (float a = deltaA; a < 1; a += deltaA)
        {
            for (float b = deltaB; b < 1; b += deltaB)
            {
                if (a + b > 1)
                    break;
                float3 pos = tri[0] * a + tri[1] * b + tri[2] * (1 - a - b);
                float2 uv = triuv[0] * a + triuv[1] * b + triuv[2] * (1 - a - b);
                sampleMaterial(pos, uv);
            }
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

        float3 baseColor = currentBaseColor->SampleArea(uvs).xyz();
        float4 spec;
        if (currentSpecular)
            spec = currentSpecular->SampleArea(uvs);
        else
            spec = float4(0, 0, 0, 0);
        ABSDFInput input = {baseColor, spec};
        ABSDF absdf = MaterialUtility::CalcABSDF(input);
        diffuseBuffer[index] += absdf.diffuse;
        specularBuffer[index] += absdf.specular;
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
            float3 positions[3] = {pPos[triangle.x], pPos[triangle.y], pPos[triangle.z]};
            // 世界坐标处理成网格坐标
            for (int i = 0; i < 3; i++)
            {
                positions[i] = (positions[i] - gridData.gridMin) / gridData.voxelSize;
            }
            float2 triuv[3] = {pUV[triangle.x], pUV[triangle.y], pUV[triangle.z]};
            if (sampleFrequency == 0)
                calcTriangle(positions, triuv);
            else
                sampleTriangle(positions, triuv);
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
        f.write(reinterpret_cast<char*>(diffuseBuffer), voxelCount * sizeof(float4));
        f.write(reinterpret_cast<char*>(specularBuffer), voxelCount * sizeof(float4));
        f.write(reinterpret_cast<char*>(ellipsoids), voxelCount * sizeof(Ellipsoid));

        f.close();
        VoxelizationBase::FileUpdated = true;
    }
};
