#pragma once
#include "Voxel/VoxelGrid.slang"
#include "Voxel/ABSDF.slang"
#include "Math/Ellipsoid.slang"
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "Math/VoxelizationUtility.h"
#include "Math/Random.h"
#include "VoxelizationShared.slang"
#include <random>
using namespace Falcor;

inline std::string ToString(size_t n)
{
    std::ostringstream oss;
    oss << n;
    return oss.str();
}
inline std::string ToString(float3 v)
{
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(4);
    oss << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    return oss.str();
}
inline std::string ToString(int2 v)
{
    std::ostringstream oss;
    oss << "(" << v.x << ", " << v.y << ")";
    return oss.str();
}
inline std::string ToString(int3 v)
{
    std::ostringstream oss;
    oss << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    return oss.str();
}

struct BufferDesc
{
    std::string name;
    std::string texname; // 如果不直接对应着色器资源，设为空字符串
    std::string desc;
    bool serialized;
    bool isInputOrOutut;
    size_t bytesPerElement;
};
using BufferlList = std::vector<BufferDesc>;

inline std::string kGBuffer = "gBuffer";
inline std::string kVBuffer = "vBuffer";
inline std::string kPolygonBuffer = "polygonBuffer";
inline std::string kBlockMap = "blockMap";

class VoxelizationBase
{
public:
    static const int NDFLobeCount = 8;
    static GridData GlobalGridData;
    static uint3 MinFactor; // 网格的分辨率必须是此值的整数倍
    static bool FileUpdated;
    static std::string ResourceFolder;

    static void UpdateVoxelGrid(ref<Scene> scene, uint voxelResolution)
    {
        float3 diag;
        float length;
        float3 center;
        if (scene)
        {
            AABB aabb = scene->getSceneBounds();
            diag = aabb.maxPoint - aabb.minPoint;
            length = std::max(diag.z, std::max(diag.x, diag.y));
            center = aabb.center();
            diag *= 1.02f;
            length *= 1.02f;
        }
        else
        {
            diag = float3(1);
            length = 1.f;
            center = float3(0);
        }

        GlobalGridData.voxelSize = float3(length / voxelResolution);
        float3 temp = diag / GlobalGridData.voxelSize;

        GlobalGridData.voxelCount = uint3(
            (uint)math::ceil(temp.x / MinFactor.x) * MinFactor.x,
            (uint)math::ceil(temp.y / MinFactor.y) * MinFactor.y,
            (uint)math::ceil(temp.z / MinFactor.z) * MinFactor.z
        );
        GlobalGridData.gridMin = center - 0.5f * GlobalGridData.voxelSize * float3(GlobalGridData.voxelCount);
        GlobalGridData.solidVoxelCount = 0;
    }
};

struct SceneHeader
{
    uint meshCount;
    uint vertexCount;
    uint triangleCount;
};

struct MeshHeader
{
    uint materialID;
    uint vertexCount;
    uint triangleCount;
    uint triangleOffset;
};

class StructuredBufferGroup
{
private:
    ref<Device> mpDevice;
    std::vector<ref<Buffer>> mBuffers;
    size_t sizePerElement;
    size_t totalSize;
    size_t maxSizePerBuffer;

public:
    StructuredBufferGroup(ref<Device> device, size_t sizePerElement, size_t maxSizePerBuffer)
        : mpDevice(device), sizePerElement(sizePerElement), totalSize(0), maxSizePerBuffer(maxSizePerBuffer)
    {
        FALCOR_ASSERT(maxSizePerBuffer % sizePerElement == 0);
    }

    uint getSizeOfBuffer(uint index) const
    {
        FALCOR_ASSERT(index < mBuffers.size());
        if (index < mBuffers.size() - 1)
            return maxSizePerBuffer;
        if (index == mBuffers.size() - 1)
            return totalSize - maxSizePerBuffer * (mBuffers.size() - 1);
        return 0;
    }

    uint getElementCountOfBuffer(uint index) const { return getSizeOfBuffer(index) / sizePerElement; }

    uint maxElementCountPerBuffer() const { return maxSizePerBuffer / sizePerElement; }

    uint size() const { return mBuffers.size(); }

    ref<Buffer> get(uint index)
    {
        FALCOR_ASSERT(index < mBuffers.size());
        return mBuffers[index];
    }

    void setBlob(const void* pData, size_t size)
    {
        FALCOR_ASSERT(size % sizePerElement == 0);
        mBuffers.clear();
        totalSize = size;
        size_t offset = 0;
        while (size > 0)
        {
            size_t copySize = std::min(size, maxSizePerBuffer);
            size_t elementCount = copySize / sizePerElement;
            ref<Buffer> buffer = mpDevice->createStructuredBuffer(
                sizePerElement, elementCount, ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource
            );
            buffer->setBlob((const char*)pData + offset, 0, copySize);
            mBuffers.push_back(buffer);
            offset += copySize;
            size -= copySize;
        }
    }
};
