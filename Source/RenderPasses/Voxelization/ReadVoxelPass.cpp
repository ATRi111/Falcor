#include "ReadVoxelPass.h"
#include "Shading.slang"
#include "RenderGraph/RenderPassStandardFlags.h"

namespace
{
const std::string kPrepareProgramFile = "RenderPasses/Voxelization/PrepareShadingData.cs.slang";

struct LegacyVoxelData
{
    ABSDF ABSDF;
    Ellipsoid ellipsoid;
    SphericalFunc primitiveProjAreaFunc;
    SphericalFunc polygonsProjAreaFunc;
    SphericalFunc totalProjAreaFunc;
};

bool doesGridLayoutRequireRecompile(const GridData& current, const GridData& loaded)
{
    return current.voxelCount.x != loaded.voxelCount.x || current.voxelCount.y != loaded.voxelCount.y || current.voxelCount.z != loaded.voxelCount.z ||
           current.solidVoxelCount != loaded.solidVoxelCount;
}

}; // namespace

ReadVoxelPass::ReadVoxelPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice), gridData(VoxelizationBase::GlobalGridData)
{
    mComplete = true;
    mOptionsChanged = false;
    selectedFile = 0;
    mpDevice = pDevice;

    // 支持从脚本传入 binFile 路径自动触发读取
    if (props.has("binFile"))
    {
        mAutoBinFile = props["binFile"].operator std::filesystem::path();
    }
}

RenderPassReflection ReadVoxelPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addInput("dummy", "Dummy")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::RGBA32Float)
        .texture2D(0, 0, 1, 1);

    reflector.addOutput(kVBuffer, kVBuffer)
        .bindFlags(ResourceBindFlags::None)
        .format(ResourceFormat::R32Uint)
        .texture3D(gridData.voxelCount.x, gridData.voxelCount.y, gridData.voxelCount.z, 1);

    reflector.addOutput(kGBuffer, kGBuffer)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(PrimitiveBSDF));

    reflector.addOutput(kPBuffer, kPBuffer)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(Ellipsoid));

    reflector.addOutput(kBlockMap, kBlockMap)
        .bindFlags(ResourceBindFlags::None)
        .format(ResourceFormat::RGBA32Uint)
        .texture2D(gridData.blockCount().x, gridData.blockCount().y);

    reflector.addOutput(kSolidVoxelCellBuffer, "Solid voxel cell coordinates")
        .bindFlags(ResourceBindFlags::ShaderResource)
        .format(ResourceFormat::Unknown)
        .rawBuffer(gridData.solidVoxelCount * sizeof(int3))
        .flags(RenderPassReflection::Field::Flags::Optional);

    return reflector;
}

void ReadVoxelPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mComplete)
        tryQueueAutoBinFile();

    if (mComplete)
        return;

    auto& dict = renderData.getDictionary();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        mOptionsChanged = false;
    }

    if (!mPreparePass)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary(kPrepareProgramFile).csEntry("main");
        desc.addTypeConformances(mpScene->getTypeConformances());

        DefineList defines;
        defines.add(mpScene->getSceneDefines());
        mPreparePass = ComputePass::create(mpDevice, desc, defines, true);
    }

    size_t voxelCount = gridData.totalVoxelCount();

    std::ifstream f;
    size_t offset = 0;

    f.open(filePaths[selectedFile], std::ios::binary | std::ios::ate);
    size_t fileSize = std::filesystem::file_size(filePaths[selectedFile]);
    tryRead(f, offset, sizeof(GridData), nullptr, fileSize);

    ref<Texture> pVBuffer = renderData.getTexture(kVBuffer);
    uint* vBuffer = new uint[gridData.totalVoxelCount()];
    tryRead(f, offset, gridData.totalVoxelCount() * sizeof(uint), vBuffer, fileSize);
    pVBuffer->setSubresourceBlob(0, vBuffer, gridData.totalVoxelCount() * sizeof(uint));

    ref<Buffer> pSolidVoxelCellBuffer = renderData.getResource(kSolidVoxelCellBuffer) ? renderData.getResource(kSolidVoxelCellBuffer)->asBuffer() : nullptr;
    std::vector<int3> solidVoxelCells;
    if (pSolidVoxelCellBuffer)
    {
        solidVoxelCells.resize(gridData.solidVoxelCount, int3(0));
        const uint3 dims = gridData.voxelCount;
        const size_t xyStride = size_t(dims.x) * size_t(dims.y);
        for (size_t linearIndex = 0; linearIndex < voxelCount; ++linearIndex)
        {
            const int voxelOffset = static_cast<int>(vBuffer[linearIndex]);
            if (voxelOffset < 0 || voxelOffset >= static_cast<int>(gridData.solidVoxelCount))
                continue;

            const uint z = uint(linearIndex / xyStride);
            const size_t xyIndex = linearIndex - size_t(z) * xyStride;
            const uint y = uint(xyIndex / dims.x);
            const uint x = uint(xyIndex - size_t(y) * dims.x);
            solidVoxelCells[size_t(voxelOffset)] = int3(int(x), int(y), int(z));
        }
        pSolidVoxelCellBuffer->setBlob(solidVoxelCells.data(), 0, solidVoxelCells.size() * sizeof(int3));
    }
    delete[] vBuffer;

    const size_t currentVoxelDataBytes = size_t(gridData.solidVoxelCount) * sizeof(VoxelData);
    const size_t legacyVoxelDataBytes = size_t(gridData.solidVoxelCount) * sizeof(LegacyVoxelData);
    const size_t blockMapBytes = size_t(gridData.totalBlockCount()) * sizeof(uint4);
    const size_t remainingBytes = fileSize - offset;
    const bool useCurrentLayout = remainingBytes == currentVoxelDataBytes + blockMapBytes;
    const bool useLegacyLayout = remainingBytes == legacyVoxelDataBytes + blockMapBytes;
    if (!useCurrentLayout && !useLegacyLayout)
    {
        logWarning(
            "ReadVoxelPass: incompatible cache layout '{}' (remaining={} bytes, expected current={} or legacy={} plus blockMap={}).",
            filePaths[selectedFile].string(),
            remainingBytes,
            currentVoxelDataBytes,
            legacyVoxelDataBytes,
            blockMapBytes
        );
        mComplete = true;
        return;
    }

    mpVoxelDataBuffer = mpDevice->createStructuredBuffer(sizeof(VoxelData), gridData.solidVoxelCount, ResourceBindFlags::ShaderResource);
    VoxelData* voxelDataBuffer = new VoxelData[gridData.solidVoxelCount];
    if (useCurrentLayout)
    {
        tryRead(f, offset, currentVoxelDataBytes, voxelDataBuffer, fileSize);
    }
    else
    {
        LegacyVoxelData* legacyVoxelDataBuffer = new LegacyVoxelData[gridData.solidVoxelCount];
        tryRead(f, offset, legacyVoxelDataBytes, legacyVoxelDataBuffer, fileSize);
        for (size_t i = 0; i < gridData.solidVoxelCount; ++i)
        {
            voxelDataBuffer[i].ABSDF = legacyVoxelDataBuffer[i].ABSDF;
            voxelDataBuffer[i].ellipsoid = legacyVoxelDataBuffer[i].ellipsoid;
            voxelDataBuffer[i].primitiveProjAreaFunc = legacyVoxelDataBuffer[i].primitiveProjAreaFunc;
            voxelDataBuffer[i].polygonsProjAreaFunc = legacyVoxelDataBuffer[i].polygonsProjAreaFunc;
            voxelDataBuffer[i].totalProjAreaFunc = legacyVoxelDataBuffer[i].totalProjAreaFunc;
            voxelDataBuffer[i].dominantInstanceID = kInvalidVoxelInstanceID;
            voxelDataBuffer[i].identityConfidence = 0.f;
        }
        delete[] legacyVoxelDataBuffer;
        logWarning(
            "ReadVoxelPass: cache '{}' uses the legacy voxel contract. identity/confidence were reset; regenerate this cache for Phase3 validation.",
            filePaths[selectedFile].string()
        );
    }
    mpVoxelDataBuffer->setBlob(voxelDataBuffer, 0, gridData.solidVoxelCount * sizeof(VoxelData));
    delete[] voxelDataBuffer;
    pRenderContext->submit(true);

    ref<Texture> pBlockMap = renderData.getTexture(kBlockMap);
    uint4* blockMap = new uint4[gridData.totalBlockCount()];
    tryRead(f, offset, gridData.totalBlockCount() * sizeof(uint4), blockMap, fileSize);
    pBlockMap->setSubresourceBlob(0, blockMap, gridData.totalBlockCount() * sizeof(uint4));
    delete[] blockMap;

    // VoxelData将拆分成PrimitiveBSDF和Ellipsoid
    ref<Buffer> pGBuffer = renderData.getResource(kGBuffer)->asBuffer();
    ref<Buffer> pPBuffer = renderData.getResource(kPBuffer)->asBuffer();

    ShaderVar var = mPreparePass->getRootVar();
    var["voxelDataBuffer"] = mpVoxelDataBuffer;
    var[kGBuffer] = pGBuffer;
    var[kPBuffer] = pPBuffer;

    auto cb = var["CB"];
    cb["voxelCount"] = (uint)gridData.solidVoxelCount;
    mPreparePass->execute(pRenderContext, uint3((uint)gridData.solidVoxelCount, 1, 1));
    pRenderContext->submit(true);
    mComplete = true;
}

void ReadVoxelPass::compile(RenderContext* pRenderContext, const CompileData& compileData) {}

void ReadVoxelPass::renderUI(Gui::Widgets& widget)
{
    if (gVoxelizationFilesUpdated)
    {
        filePaths.clear();
        const auto& resourceFolder = getVoxelizationResourceFolderPath();
        if (std::filesystem::exists(resourceFolder))
        {
            for (const auto& entry : std::filesystem::directory_iterator(resourceFolder))
            {
                if (std::filesystem::is_regular_file(entry))
                {
                    filePaths.push_back(entry.path());
                }
            }
        }
        gVoxelizationFilesUpdated = false;
    }

    if (filePaths.empty())
    {
        widget.text("No voxel cache files found in " + getVoxelizationResourceFolderPath().string());
        return;
    }

    selectedFile = std::min(selectedFile, uint(filePaths.size() - 1));
    Gui::DropdownList list;
    for (uint i = 0; i < filePaths.size(); i++)
    {
        list.push_back({i, filePaths[i].filename().string()});
    }
    widget.dropdown("File", list, selectedFile);

    if (mpScene && widget.button("Read"))
    {
        std::ifstream f;
        size_t offset = 0;

        f.open(filePaths[selectedFile], std::ios::binary | std::ios::ate);
        if (!f.is_open())
            return;

        size_t fileSize = std::filesystem::file_size(filePaths[selectedFile]);
        tryRead(f, offset, sizeof(GridData), &gridData, fileSize);

        f.close();

        requestRecompile();
        mComplete = false;
        mOptionsChanged = true;
    }

    GridData& data = VoxelizationBase::GlobalGridData;
    widget.text("Voxel Size: " + ToString(data.voxelSize));
    widget.text("Voxel Count: " + ToString((int3)data.voxelCount));
    widget.text("Block Count: " + ToString((int3)data.blockCount3D()));
    widget.text("Grid Min: " + ToString(data.gridMin));
    widget.text("Solid Voxel Count: " + std::to_string(data.solidVoxelCount));
    widget.text("Solid Rate: " + std::to_string(data.solidVoxelCount / (float)data.totalVoxelCount()));
    widget.text("Max Polygon Count: " + std::to_string(data.maxPolygonCount));
    widget.text("Total Polygon Count: " + std::to_string(data.totalPolygonCount));
}

void ReadVoxelPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    // 如果脚本指定了 binFile，场景加载后自动触发读取
    tryQueueAutoBinFile();
}

bool ReadVoxelPass::tryQueueAutoBinFile()
{
    if (mAutoBinFileQueued || mAutoBinFile.empty() || !std::filesystem::exists(mAutoBinFile))
        return false;

    std::ifstream f(mAutoBinFile, std::ios::binary | std::ios::ate);
    if (!f.is_open())
        return false;

    size_t offset = 0;
    size_t fileSize = std::filesystem::file_size(mAutoBinFile);
    GridData loadedGridData = {};
    if (!tryRead(f, offset, sizeof(GridData), &loadedGridData, fileSize))
        return false;

    f.close();

    const bool requiresRecompile = doesGridLayoutRequireRecompile(gridData, loadedGridData);
    gridData = loadedGridData;

    filePaths.clear();
    filePaths.push_back(mAutoBinFile);
    selectedFile = 0;

    if (requiresRecompile)
        requestRecompile();
    mComplete = false;
    mOptionsChanged = true;
    mAutoBinFileQueued = true;
    return true;
}

bool ReadVoxelPass::tryRead(std::ifstream& f, size_t& offset, size_t bytes, void* dst, size_t fileSize)
{
    if (offset + bytes > fileSize)
        return false;
    if (dst)
    {
        f.seekg(offset, std::ios::beg);
        f.read(reinterpret_cast<char*>(dst), bytes);
    }
    offset += bytes;
    return true;
}
