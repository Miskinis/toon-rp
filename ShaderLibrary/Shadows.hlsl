#ifndef TOON_RP_SHADOWS
#define TOON_RP_SHADOWS

#if defined(_TOON_RP_DIRECTIONAL_SHADOWS) || defined(_TOON_RP_DIRECTIONAL_CASCADED_SHADOWS)
#define _TOON_RP_SHADOW_MAPS
#endif // _TOON_RP_DIRECTIONAL_SHADOWS || _TOON_RP_DIRECTIONAL_CASCADED_SHADOWS

#if defined(_TOON_RP_SHADOW_MAPS) || defined(_TOON_RP_BLOB_SHADOWS)
#define _TOON_RP_ANY_SHADOWS
#endif // _TOON_RP_SHADOW_MAPS || _TOON_RP_BLOB_SHADOWS

#include "Common.hlsl"
#include "Math.hlsl"
#include "Ramp.hlsl"
#include "VSM.hlsl"

#define MAX_DIRECTIONAL_LIGHT_COUNT 1
#define MAX_ADDITIONAL_LIGHT_SHADOWS_COUNT 16
#define MAX_POINT_SHADOW_FACES 6

// One tile per cubemap face. Must mirror ToonShadowMaps.MaxAdditionalShadowTiles.
#define MAX_ADDITIONAL_SHADOW_TILES (MAX_ADDITIONAL_LIGHT_SHADOWS_COUNT * MAX_POINT_SHADOW_FACES)
#define MAX_CASCADE_COUNT 4

#ifdef _TOON_RP_VSM
TEXTURE2D(_ToonRP_DirectionalShadowAtlas);
SAMPLER(sampler_ToonRP_DirectionalShadowAtlas);
#else // !_TOON_RP_VSM
TEXTURE2D_SHADOW(_ToonRP_DirectionalShadowAtlas);
SAMPLER_CMP(sampler_LinearClampCompare);
#endif //_TOON_RP_VSM

TEXTURE2D(_ToonRP_ShadowPattern);
SAMPLER(sampler_ToonRP_ShadowPattern);

#ifdef _TOON_RP_VSM
TEXTURE2D(_ToonRP_AdditionalShadows);
SAMPLER(sampler_ToonRP_AdditionalShadows);
#else // !_TOON_RP_VSM
TEXTURE2D_SHADOW(_ToonRP_AdditionalShadows);
SAMPLER_CMP(sampler_ToonRP_AdditionalShadows);
#endif // _TOON_RP_VSM

CBUFFER_START(_ToonRpShadows)
    float4x4 _ToonRP_DirectionalShadowMatrices_VP[MAX_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
    int _ToonRP_CascadeCount;
    float4 _ToonRP_CascadeCullingSpheres[MAX_CASCADE_COUNT];
    float2 _ToonRP_ShadowRamp;
    float _ToonRP_ShadowLightBleedingReduction;
    float _ToonRP_ShadowPrecisionCompensation;
    float2 _ToonRP_ShadowDistanceFade;
    float2 _ToonRP_ShadowBias; // x - depth, y - normal
    float3 _ToonRP_ShadowPatternScale;
    float _ToonRP_ShadowPatternStrength;

    float4x4 _ToonRP_AdditionalShadowMatrices_VP[MAX_ADDITIONAL_SHADOW_TILES];
    half4 _ToonRP_AdditionalShadows_Metadata[MAX_ADDITIONAL_LIGHT_SHADOWS_COUNT];

    uint _ToonRP_PoissonDiskSize;
    float _ToonRP_fPoissonDiskSize;
    float _ToonRP_InvPoissonDiskSize;
    float2 _ToonRP_DirectionalShadowPoissonDisk[16];
CBUFFER_END

TEXTURE3D(_ToonRP_RotatedPoissonSamplingTexture);
SAMPLER(sampler_ToonRP_RotatedPoissonSamplingTexture);

float _ToonRP_AdditionalShadowTexelSize;
float _ToonRP_AdditionalShadowFilterScale;
// Number of tiles along one axis of the additional shadow atlas.
float _ToonRP_AdditionalShadows_Split;

float3 ApplyShadowBias(float3 positionWs, const float3 normalWs, const float3 lightDirection)
{
    const float invNDotL = 1.0 - saturate(dot(lightDirection, normalWs));
    float scale = invNDotL * _ToonRP_ShadowBias.y;

    // normal bias is negative since we want to apply an inset normal offset
    positionWs = lightDirection * _ToonRP_ShadowBias.xxx + positionWs;
    positionWs = normalWs * scale.xxx + positionWs;
    return positionWs;
}

#ifndef _TOON_RP_VSM

float SampleShadowAttenuationNonVsm(const float3 shadowCoords)
{
    return SAMPLE_TEXTURE2D_SHADOW(_ToonRP_DirectionalShadowAtlas, sampler_LinearClampCompare,
                                   shadowCoords).r;
}

float PoissonPcfHash(const float4 seed4)
{
    const float dotProduct = dot(seed4, float4(12.9898, 78.233, 45.164, 94.673));
    return frac(sin(dotProduct) * 43758.5453);
}

float2 SampleRotatedPoissonSamplingTexture(const float3 positionWs)
{
    const float3 uv = positionWs * 1000;
    float2 rotation = SAMPLE_TEXTURE3D(_ToonRP_RotatedPoissonSamplingTexture,
                                       sampler_ToonRP_RotatedPoissonSamplingTexture, uv).xy;
    rotation = rotation * 2 - 1;
    return rotation;
}

float SampleShadowAttenuationNonVsmFiltered(const float3 shadowCoords, const float3 positionWs)
{
    float attenuation = 0;

    #ifdef _TOON_RP_POISSON_SAMPLING_ROTATED
    const float2 rotation = SampleRotatedPoissonSamplingTexture(positionWs);
    #endif // _TOON_RP_POISSON_SAMPLING_ROTATED

    UNITY_LOOP
    for (uint i = 0; i < _ToonRP_PoissonDiskSize; ++i)
    {
        float2 poissonSample;

        #if defined(_TOON_RP_POISSON_SAMPLING_STRATIFIED)
        const uint diskSampleIndex = (uint)(_ToonRP_fPoissonDiskSize * PoissonPcfHash(float4(positionWs, i)) % _ToonRP_fPoissonDiskSize);
        poissonSample = _ToonRP_DirectionalShadowPoissonDisk[diskSampleIndex];
        #elif defined(_TOON_RP_POISSON_SAMPLING_ROTATED)
        poissonSample = _ToonRP_DirectionalShadowPoissonDisk[i];
        poissonSample = float2(
            rotation.x * poissonSample.x - rotation.y * poissonSample.y,
            rotation.y * poissonSample.x + rotation.x * poissonSample.y
            );
        #else
        poissonSample = _ToonRP_DirectionalShadowPoissonDisk[i];
        #endif
        attenuation += SampleShadowAttenuationNonVsm(shadowCoords + float3(poissonSample, 0));

        #ifdef _TOON_RP_POISSON_SAMPLING_EARLY_BAIL
        // Early bail: if first four samples are all zeroes or ones, assume the rest is the same
        if (i == 4 && (attenuation == 0.0f || attenuation == 4.0f))
        {
            return attenuation / 4.0f;
        }
        #endif // _TOON_RP_POISSON_SAMPLING_EARLY_BAIL
    }

    return attenuation * _ToonRP_InvPoissonDiskSize;
}

#endif // !_TOON_RP_VSM

float SampleShadowAttenuation(const float3 shadowCoords, const float3 positionWs)
{
    #if defined(_TOON_RP_VSM)
    const float2 varianceSample = SAMPLE_TEXTURE2D(_ToonRP_DirectionalShadowAtlas,
                                                   sampler_ToonRP_DirectionalShadowAtlas,
                                                   shadowCoords.xy).rg;
    const float variance = varianceSample.y - varianceSample.x * varianceSample.x + _ToonRP_ShadowPrecisionCompensation;

    #ifdef UNITY_REVERSED_Z
    const float difference = shadowCoords.z - varianceSample.x;
    #else // !UNITY_REVERSED_Z
    const float difference = varianceSample.x - shadowCoords.z;
    #endif // UNITY_REVERSED_Z

    if (difference > 0.00001)
    {
        return InverseLerpClamped(_ToonRP_ShadowLightBleedingReduction, 1.0, variance / (variance + difference * difference));
    }

    return 1.0;
    #elif defined(_TOON_RP_PCF)
    return SampleShadowAttenuationNonVsmFiltered(shadowCoords, positionWs);
    #else // !_TOON_RP_VSM && !_TOON_RP_PCF
    return SampleShadowAttenuationNonVsm(shadowCoords);
    #endif
}

float2 ClampAdditionalShadowUvToTile(const float2 uv, const uint tileIndex)
{
    const int split = max((int) _ToonRP_AdditionalShadows_Split, 1);
    const float tileSize = 1.0f / split;
    const int tileX = (int) (tileIndex % (uint) split);
    const int tileY = (int) (tileIndex / (uint) split);
    const float2 tileMin = float2(tileX, tileY) * tileSize;
    const float2 tileMax = tileMin + tileSize;
    // Inset by half a texel so bilinear taps never reach the neighbouring tile.
    const float halfTexel = _ToonRP_AdditionalShadowTexelSize * 0.5f;
    return clamp(uv, tileMin + halfTexel, tileMax - halfTexel);
}

float SampleAdditionalShadowAttenuation(const float3 shadowCoords, const uint shadowIndex)
{
    const float2 shadowUv = ClampAdditionalShadowUvToTile(shadowCoords.xy, shadowIndex);

    #ifdef _TOON_RP_VSM
    const float2 varianceSample = SAMPLE_TEXTURE2D(
        _ToonRP_AdditionalShadows, sampler_ToonRP_AdditionalShadows, shadowUv
    ).rg;
    const float variance = varianceSample.y - varianceSample.x * varianceSample.x +
        _ToonRP_ShadowPrecisionCompensation;

    #ifdef UNITY_REVERSED_Z
    const float difference = shadowCoords.z - varianceSample.x;
    #else // !UNITY_REVERSED_Z
    const float difference = varianceSample.x - shadowCoords.z;
    #endif // UNITY_REVERSED_Z

    if (difference > 0.00001)
    {
        return InverseLerpClamped(
            _ToonRP_ShadowLightBleedingReduction, 1.0, variance / (variance + difference * difference)
        );
    }

    return 1.0;
    #else // !_TOON_RP_VSM
    return SAMPLE_TEXTURE2D_SHADOW(_ToonRP_AdditionalShadows, sampler_ToonRP_AdditionalShadows,
                                   float3(shadowUv, shadowCoords.z)).r;
    #endif // _TOON_RP_VSM
}

float SampleAdditionalShadowAttenuationFiltered(const float3 shadowCoords, const uint shadowIndex)
{
    float attenuation = SampleAdditionalShadowAttenuation(shadowCoords, shadowIndex);

    #ifndef _TOON_RP_VSM
    if (_ToonRP_AdditionalShadowFilterScale > 0)
    {
        const float2 texel = _ToonRP_AdditionalShadowTexelSize.xx * _ToonRP_AdditionalShadowFilterScale;

        attenuation = 0;
        attenuation += SampleAdditionalShadowAttenuation(
            shadowCoords + float3(-texel.x, -texel.y, 0), shadowIndex
        );
        attenuation += SampleAdditionalShadowAttenuation(
            shadowCoords + float3(texel.x, -texel.y, 0), shadowIndex
        );
        attenuation += SampleAdditionalShadowAttenuation(
            shadowCoords + float3(-texel.x, texel.y, 0), shadowIndex
        );
        attenuation += SampleAdditionalShadowAttenuation(
            shadowCoords + float3(texel.x, texel.y, 0), shadowIndex
        );
        attenuation *= 0.25;
    }
    #endif // _TOON_RP_VSM

    return attenuation;
}

float SampleShadowPattern(const float3 positionWs)
{
    const float2 uv = EncodePositionToUv(positionWs, _ToonRP_ShadowPatternScale);
    return SAMPLE_TEXTURE2D(_ToonRP_ShadowPattern, sampler_ToonRP_ShadowPattern, uv).r;
}

uint ComputeShadowTileIndex(const float3 positionWs)
{
    #ifdef _TOON_RP_DIRECTIONAL_CASCADED_SHADOWS
    
    int i;
    for (i = 0; i < _ToonRP_CascadeCount; i++)
    {
        float4 sphere = _ToonRP_CascadeCullingSpheres[i];
        const float distanceSqr = DistanceSquared(positionWs, sphere.xyz);
        if (distanceSqr < sphere.w)
        {
            return i;
        }
    }
    return _ToonRP_CascadeCount - 1;

    #else // !_TOON_RP_DIRECTIONAL_CASCADED_SHADOWS

    return 0;

    #endif // _TOON_RP_DIRECTIONAL_CASCADED_SHADOWS
}

float3 TransformWorldToShadowCoords(const float3 positionWs, uint tileIndex, const bool perspectiveProjection = false)
{
    float4 shadowCoords = mul(_ToonRP_DirectionalShadowMatrices_VP[tileIndex], float4(positionWs, 1.0f));

    if (perspectiveProjection)
    {
        shadowCoords.xyz /= shadowCoords.w;
    }

    return shadowCoords.xyz;
}

float3 TransformWorldToAdditionalShadowCoords(const float3 positionWs, uint shadowIndex, const bool perspectiveProjection = true)
{
    float4 shadowCoords = mul(_ToonRP_AdditionalShadowMatrices_VP[shadowIndex], float4(positionWs, 1.0f));

    if (perspectiveProjection)
    {
        // The atlas coordinates are perspective-projected, but the VSM depth is the packed linear
        // view-space depth produced by GetPackedVsmDepth in the shadow caster, so it must not be
        // divided by w (unlike the hardware depth compare used in the non-VSM path).
        shadowCoords.xy /= shadowCoords.w;

        #ifndef _TOON_RP_VSM
        shadowCoords.z /= shadowCoords.w;
        #endif // !_TOON_RP_VSM
    }

    return shadowCoords.xyz;
}

// Matches Unity's CubemapFace order: +X, -X, +Y, -Y, +Z, -Z.
int ComputePointShadowFace(const float3 lightToPosition)
{
    const float3 absDirection = abs(lightToPosition);

    if (absDirection.x >= absDirection.y && absDirection.x >= absDirection.z)
    {
        return lightToPosition.x >= 0.0f ? 0 : 1;
    }

    if (absDirection.y >= absDirection.z)
    {
        return lightToPosition.y >= 0.0f ? 2 : 3;
    }

    return lightToPosition.z >= 0.0f ? 4 : 5;
}

float SamplePointShadowAttenuation(const float3 positionWs, const float3 lightPositionWs, const int baseTile,
                                   const int faceMask)
{
    const int face = ComputePointShadowFace(positionWs - lightPositionWs);
    if ((faceMask & (1 << face)) == 0)
    {
        // The face failed to render this frame (or was never rendered), so do not sample its stale tile.
        return 1.0f;
    }

    const uint shadowIndex = (uint) (baseTile + face);
    const float3 shadowCoords = TransformWorldToAdditionalShadowCoords(positionWs, shadowIndex);
    return SampleAdditionalShadowAttenuationFiltered(shadowCoords, shadowIndex);
}

float ComputeShadowRamp(const float shadowAttenuation)
{
    float ramp;
    #ifdef _TOON_RP_SHADOWS_RAMP_CRISP
    ramp = StepAntiAliased(_ToonRP_ShadowRamp.x, shadowAttenuation);
    #else // !_TOON_RP_SHADOWS_RAMP_CRISP
    ramp = ComputeRamp(shadowAttenuation, _ToonRP_ShadowRamp);
    #endif // _TOON_RP_SHADOWS_RAMP_CRISP
    return ramp;
}

float ComputeShadowDistanceFade(const float3 positionWs)
{
    const float distanceCamToPixel2 = DistanceSquared(positionWs, _WorldSpaceCameraPos);
    const float fade = DistanceFade(distanceCamToPixel2, _ToonRP_ShadowDistanceFade.x, _ToonRP_ShadowDistanceFade.y);
    return fade;
}

#endif // TOON_RP_SHADOWS