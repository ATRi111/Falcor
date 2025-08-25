#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR
enum class MyRasterMode : uint32_t
{
    BlinnPhong,
    GGX,
};

FALCOR_ENUM_INFO(
    MyRasterMode,
    {
        { MyRasterMode::BlinnPhong, "BlinnPhong" },
        { MyRasterMode::GGX, "GGX" },
    }
);
FALCOR_ENUM_REGISTER(MyRasterMode);

END_NAMESPACE_FALCOR
