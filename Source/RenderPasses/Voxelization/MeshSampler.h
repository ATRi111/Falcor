#pragma once
#include "VoxelizationBase.h"

class MeshSampler
{
private:
    GridData& gridData;

public:
    MeshSampler() : gridData(VoxelizationBase::GlobalGridData) {}

    void SampleAll() {}
};
