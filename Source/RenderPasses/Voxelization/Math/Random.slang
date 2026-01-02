#pragma once
__exported import Utils.Sampling.SampleGeneratorInterface;

inline float Next(inout ISampleGenerator sg)
{
    return sg.next() / 4294967296.0;
}
inline float2 Next2(inout ISampleGenerator sg)
{
    return float2(Next(sg), Next(sg));
}
inline float3 Next3(inout ISampleGenerator sg)
{
    return float3(Next(sg), Next(sg), Next(sg));
}
