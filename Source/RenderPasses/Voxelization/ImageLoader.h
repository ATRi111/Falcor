#pragma once
#include "VoxelizationBase.h"
#include "Image.h"
#include <unordered_map>

enum TextureType
{
    BaseColor,
    Specular,
    Normal,
};

class ImageLoader
{
private:
    std::string textureFolder;
    std::unordered_map<TextureType, std::string> typeToName;
    std::unordered_map<uint, std::string> idToName_Arcade;

    std::unordered_map<std::string, Image*> imageCache;

public:
    ImageLoader();
    ~ImageLoader();
    Image* loadImage(uint materialId, TextureType type);
};
