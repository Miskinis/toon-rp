#ifndef TOON_RP_GAUSSIAN_BLUR
#define TOON_RP_GAUSSIAN_BLUR

#include "../../ShaderLibrary/Textures.hlsl"
#include "../../ShaderLibrary/VSM.hlsl"

float _EarlyBailThreshold;

#ifdef TOON_RP_VSM_BLUR_TILE_CLAMP
float _ToonRP_VSM_BlurTileSplit;
#endif // TOON_RP_VSM_BLUR_TILE_CLAMP

// https://www.rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/

#ifdef _TOON_RP_VSM_BLUR_HIGH_QUALITY

const static uint BlurKernelSize = 5;

// for early bail, make first two entries in offsets and weights symmetrical
const static float BlurOffsets[BlurKernelSize] =
{
    -1.3846153846f,
    1.3846153846f,
    -3.2307692308f,
    0.0f,
    3.2307692308f
};

const static float BlurWeights[BlurKernelSize] =
{
    0.3162162162f,
    0.3162162162f,
    0.0702702703f,
    0.2270270270f,
    0.0702702703f
};

#else // !_TOON_RP_VSM_BLUR_HIGH_QUALITY


const static uint BlurKernelSize = 3;

// low quality blur is not using early bail, arranging the offsets and weights linearly
const static float BlurOffsets[BlurKernelSize] =
{
    -1.72027972039f / 2,
    0.0f,
    1.72027972039f / 2,
};

const static float BlurWeights[BlurKernelSize] =
{
    0.3864864865f, 0.2270270270f, 0.3864864865f,
};

#endif // _TOON_RP_VSM_BLUR_HIGH_QUALITY

bool ApproximatelyEqual(const float2 v1, const float2 v2)
{
    const float2 offset = v1 - v2;
    return abs(offset.x) < _EarlyBailThreshold;
}

// Keeps the blur kernel inside the current shadow atlas tile so that it does not
// sample neighbouring point-light faces.
float2 ClampBlurUv(const float2 uv, const float2 centerUv, const float2 texelSize)
{
    #ifdef TOON_RP_VSM_BLUR_TILE_CLAMP
    const float2 tileSize = 1.0f / _ToonRP_VSM_BlurTileSplit;
    const float2 tileMin = floor(centerUv * _ToonRP_VSM_BlurTileSplit) * tileSize;
    const float2 tileMax = tileMin + tileSize;
    return clamp(uv, tileMin + texelSize * 0.5f, tileMax - texelSize * 0.5f);
    #else
    return uv;
    #endif
}

float2 Blur(TEXTURE2D_PARAM(tex, texSampler), const float2 texelSize, const float2 uv, const float2 direction)
{
    float2 value = 0;

    const float2 centerSample = SAMPLE_TEXTURE2D(tex, texSampler,
                                                 ClampBlurUv(uv + direction * BlurOffsets[0] * texelSize,
                                                     uv, texelSize
                                                 )).rg;
    value += centerSample * BlurWeights[0];

    UNITY_UNROLL
    for (uint i = 1; i < BlurKernelSize; ++i)
    {
        const float2 uvOffset = uv + direction * BlurOffsets[i] * texelSize;
        const float2 sample = SAMPLE_TEXTURE2D(tex, texSampler, ClampBlurUv(uvOffset, uv, texelSize)).rg;

        #ifdef _TOON_RP_VSM_BLUR_EARLY_BAIL
        UNITY_BRANCH
        if (i == 1)
        {
            if (ApproximatelyEqual(sample, centerSample))
            {
                return centerSample;
            }
        }
        #endif // _TOON_RP_VSM_BLUR_EARLY_BAIL

        value += sample * BlurWeights[i];
    }

    return value;
}


#endif // TOON_RP_GAUSSIAN_BLUR