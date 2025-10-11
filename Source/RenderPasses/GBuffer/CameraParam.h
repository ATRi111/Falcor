#pragma once
#include "GBufferBase.h"

struct CameraParam
{
    float3 position;
    float3 target;
    float3 up;
    float aspectRatio;
    float focalLength;
    float frameHeight;
    float farPlane;

    void ApplyToCamera(ref<Camera> camera) const
    {
        camera->setPosition(position);
        camera->setTarget(target);
        camera->setUpVector(up);
        camera->setAspectRatio(aspectRatio);
        camera->setFocalLength(focalLength);
        camera->setFrameHeight(frameHeight);
        camera->setFarPlane(farPlane);
    }

    static CameraParam FromCamera(ref<Camera> camera)
    {
        CameraParam param = {
            camera->getPosition(),
            camera->getTarget(),
            camera->getUpVector(),
            camera->getAspectRatio(),
            camera->getFocalLength(),
            camera->getFrameHeight(),
            camera->getFarPlane()
        };
        return param;
    }
};
