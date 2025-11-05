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

    int w, h, c;
    float* pixels = stbi_loadf(filePath.c_str(), &w, &h, &c, 4);
    if (!pixels)
        return nullptr;
    Image* image = new Image(reinterpret_cast<float4*>(pixels), uint2(w, h));
    image->name = filePath;
    imageCache[filePath] = image;

    stbi_image_free(pixels);
    return image;
}
