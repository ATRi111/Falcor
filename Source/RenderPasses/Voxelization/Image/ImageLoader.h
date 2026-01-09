#pragma once
#include "CPUTexture.h"
#include <unordered_map>
using namespace Falcor;

class ImageLoader
{
private:
    std::unordered_map<TextureType, std::string> typeToName;
    std::unordered_map<uint, std::string> idToPath_Arcade;
    std::unordered_map<uint, std::string> idToPath_Azalea;
    std::unordered_map<uint, std::string> idToPath_Box;
    std::unordered_map<uint, std::string> idToPath_BoxBunny;
    std::unordered_map<uint, std::string> idToPath_Chandelier;
    std::unordered_map<uint, std::string>* pIdToPath;

    std::unordered_map<std::string, CPUTexture*> imageCache;

    ImageLoader();
    ~ImageLoader();

public:
    static ImageLoader& Instance();
    CPUTexture* loadImage(uint materialId, TextureType type);
    void setSceneName(std::string sceneName);
};
