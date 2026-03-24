struct PsOut
{
    float4 color : SV_Target0;
};

PsOut main(float2 texCoord : TEXCOORD, float4 pos : SV_POSITION)
{
    PsOut psOut = {};
    psOut.color = float4(0.2f, 0.7f, 0.2f, 1.0f);
    return psOut;
}
