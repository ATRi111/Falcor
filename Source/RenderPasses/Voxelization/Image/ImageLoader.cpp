#include "ImageLoader.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

ImageLoader::ImageLoader()
{
    textureFolder = "E:/Project/Falcor/media/Arcade/Textures/";
    {
        typeToName[BaseColor] = "BaseColor";
        typeToName[Specular] = "Specular";
        typeToName[Normal] = "Normal";
    }
    {
        idToName_Arcade[0] = "Wall";
        idToName_Arcade[1] = "CheckerTile";
        idToName_Arcade[2] = "Poster";
        idToName_Arcade[3] = "Chair_Orange";
        idToName_Arcade[4] = "Chair_Blue";
        idToName_Arcade[5] = "Cabinet";
    }
    // 提前生成缓存
    for (uint i = 0; i < idToName_Arcade.size(); i++)
    {
        loadImage(i, BaseColor);
        loadImage(i, Specular);
        loadImage(i, Normal);
    }
}

ImageLoader& ImageLoader::Instance()
{
    static ImageLoader imageLoader;
    return imageLoader;
}

ImageLoader::~ImageLoader()
{
    for (auto& pair : imageCache)
    {
        free(pair.second);
    }
}

Image* ImageLoader::loadImage(uint materialId, TextureType type)
{
    std::string filePath = textureFolder + idToName_Arcade[materialId] + "_" + typeToName[type] + ".png";
    auto it = imageCache.find(filePath);
    if (it != imageCache.end())
        return it->second;

    FilterFunction filterFunction;
    switch (type)
    {
    case BaseColor:
        filterFunction = FilterFunction::Average;
        stbi_ldr_to_hdr_gamma(2.2f);
        break;
    case Normal:
        filterFunction = FilterFunction::Normalize;
        stbi_ldr_to_hdr_gamma(1.0f);
        break;
    case Specular:
        filterFunction = FilterFunction::Average;
        stbi_ldr_to_hdr_gamma(1.0f);
        break;
    }

    int w, h, c;
    float* pixels = stbi_loadf(filePath.c_str(), &w, &h, &c, 4);
    if (!pixels)
        return nullptr;

    Image* image = new Image(reinterpret_cast<float4*>(pixels), uint2(w, h), filterFunction);
    image->name = filePath;
    imageCache[filePath] = image;

    stbi_image_free(pixels);
    return image;
}
