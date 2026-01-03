#pragma once
__exported import Utils.Sampling.SampleGeneratorInterface;

inline float Next<T : ISampleGenerator>(inout T sg)
{
    return sg.next() / 4294967296.0;
}
inline float2 Next2<T : ISampleGenerator>(inout T sg)
{
    return float2(Next(sg), Next(sg));
}
inline float3 Next3<T : ISampleGenerator>(inout T sg)
{
    return float3(Next(sg), Next(sg), Next(sg));
}
