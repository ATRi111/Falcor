#pragma once
#include "Image.h"
#include <unordered_map>
using namespace Falcor;

enum TextureType
{
    BaseColor,
    Specular,
    Normal,
};

class ImageLoader
{
private:
    std::unordered_map<TextureType, std::string> typeToName;
    std::unordered_map<uint, std::string> idToPath_Arcade;
    std::unordered_map<uint, std::string>* pIdToPath;

    std::unordered_map<std::string, Image*> imageCache;

    ImageLoader();
    ~ImageLoader();

public:
    static ImageLoader& Instance();
    Image* loadImage(uint materialId, TextureType type);
    void setSceneName(std::string sceneName);
};
