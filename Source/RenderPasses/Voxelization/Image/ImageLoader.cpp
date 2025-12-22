#include "ImageLoader.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

ImageLoader::ImageLoader()
{
    pIdToPath = nullptr;
    {
        typeToName[BaseColor] = "BaseColor";
        typeToName[Specular] = "Specular";
        typeToName[Normal] = "Normal";
    }

    {
        std::string folder = "E:/Project/Falcor/Scene/Arcade/Textures/";
        idToPath_Arcade[0] = folder + "Wall";
        idToPath_Arcade[1] = folder + "CheckerTile";
        idToPath_Arcade[2] = folder + "Poster";
        idToPath_Arcade[3] = folder + "Chair_Orange";
        idToPath_Arcade[4] = folder + "Chair_Blue";
        idToPath_Arcade[5] = folder + "Cabinet";
    }

    {
        std::string folder = "E:/Project/Falcor/Scene/Box/Textures/";
        idToPath_Box[0] = folder + "Floor";
        idToPath_Box[1] = folder + "LeftWall";
        idToPath_Box[2] = folder + "RightWall";
    }

    {
        std::string folder = "E:/Project/Falcor/Scene/BoxBunny/Textures/";
        idToPath_BoxBunny[0] = folder + "Floor";
        idToPath_BoxBunny[1] = folder + "LeftWall";
        idToPath_BoxBunny[2] = folder + "RightWall";
        idToPath_BoxBunny[3] = folder + "Bunny";
    }

    {
        std::string folder = "E:/Project/Falcor/Scene/Chandelier/Textures/";
        idToPath_Chandelier[0] = folder + "Candle";
        idToPath_Chandelier[1] = folder + "Body";
        idToPath_Chandelier[2] = folder + "Pillar";
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
    if (!pIdToPath)
        return nullptr;
    std::string filePath = (*pIdToPath)[materialId] + "_" + typeToName[type] + ".png";
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
    {
        imageCache[filePath] = nullptr;
        return nullptr;
    }

    Image* image = new Image(reinterpret_cast<float4*>(pixels), uint2(w, h), filterFunction);
    image->name = filePath;
    imageCache[filePath] = image;

    stbi_image_free(pixels);
    return image;
}

void ImageLoader::setSceneName(std::string sceneName)
{
    if (sceneName == "Arcade")
        pIdToPath = &idToPath_Arcade;
    else if (sceneName == "Box")
        pIdToPath = &idToPath_Box;
    else if (sceneName == "BoxBunny")
        pIdToPath = &idToPath_BoxBunny;
    else if (sceneName == "Chandelier")
        pIdToPath = &idToPath_Chandelier;
    else
        pIdToPath = nullptr;
}
