#pragma once
import Utils.Sampling.UniformSampleGenerator;

inline double Next(inout UniformSampleGenerator sg)
{
    return sg.next() / 4294967296.0;
}
inline float2 Next2(inout UniformSampleGenerator sg)
{
    return float2((float)Next(sg), (float)Next(sg));
}
inline float3 Next3(inout UniformSampleGenerator sg)
{
    return float3((float)Next(sg), (float)Next(sg), (float)Next(sg));
}
