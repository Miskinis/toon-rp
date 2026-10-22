# Toon RP

For relevant documentation, please visit [the repository](https://github.com/Delt06/toon-rp).

Host-project references (Ancient Privateers):

- [Toon RP Shadows — Usage Matrix](../specs/toon-rp-shadow-usage/core/usage.md)
- [Upstream issue mapping](../specs/archive/point-light-shadows/upstream-issues.md)

## Directional Shadow Strength

The main directional light's `Shadow Strength` now scales the toon-ramped directional shadow. `0` removes the shadow, `1` is the previous full-strength look, and `0.5` produces a half-strength ramped mask. The strength is applied after the toon shadow ramp/pattern and before SSAO; the baked-GI subtraction applies the same value once. The blob-shadow and ShaderGraph main-light occlusion paths use the same value.

## Point Light Shadows

Point lights can cast real-time shadows into the same additional-light shadow atlas used by spot lights. The feature is opt-in:

1. In the pipeline asset, enable `Shadows/Shadow Maps/Additional`.
2. Enable `Point`.
3. On each point light, set `Shadow Type` to `Hard Shadows` or `Soft Shadows` and keep `Shadow Strength` above `0`.
4. Make sure the light is `Realtime`. Baked lights do not cast real-time shadows; mixed lights cast only when Unity supplies real-time shadow data for them.

### How it works

A point light is rendered into six atlas tiles, one per cubemap face (`+X`, `-X`, `+Y`, `-Y`, `+Z`, `-Z`). The view and projection matrices come from `CullingResults.ComputePointShadowMatricesAndCullingPrimitives`. At shading time, the face is selected from the dominant axis of the light-to-fragment direction, and the matching atlas tile is sampled.

Spot and point lights can be mixed freely. Each light keeps its own atlas tile range.

Point and spot shadow attenuation is passed through the same toon shadow ramp and pattern as the directional shadows. Assign `ShadowSettings/Pattern` (for example `Assets/Main/ShadowPattern.png`) to turn the hard cast shadow into the project's stylized mask; the pattern is sampled in world space and controlled by `PatternScale`. `ShadowSettings/Pattern Strength` multiplies the sampled mask (default `3`, which keeps the stylized point/spot look). Partial `Shadow Strength` is applied after the ramp, so `0.5` produces a half-strength shadow rather than pushing the raw attenuation across the toon threshold.

### Quality settings

Point shadows share the additional-light atlas and use the same VSM path as directional shadows: a two-channel moments atlas, a Gaussian blur, and the same light-bleeding reduction and precision compensation.

- Set `Additional/Atlas Size` to `2048` or `4096`. A point light consumes six tiles, so the per-face resolution is `atlasSize / ceil(sqrt(totalTiles))`.
- Sampling and blurring are clamped to each atlas tile (with a half-texel inset), so bilinear taps never bleed into a neighbouring cubemap face. This covers the Gaussian and Box passes for both the directional cascade atlas and the additional atlas.
- Early-bail blur returns the true center texel, not the first offset tap.
- `Additional/Point/Fov Bias` (default `2`) is the extra field of view above 90 degrees passed to `ComputePointShadowMatricesAndCullingPrimitives`. Low-height, long-range point lights may need a larger bias to keep casters inside every face. `0` removes the overlap between faces and can expose seams.
- `Blur` (`Box`, `Gaussian Low Quality`, `Gaussian High Quality`), `Blur Scatter`, `Blur Early Bail`, `Light Bleeding Reduction`, `VSM Precision`, and `Precision Compensation` apply to both shadow atlases.
- `Soft Shadows/Spread` only affects the non-VSM PCF path. With VSM, shadow softness comes from `Blur Scatter`.
- Use the light's `Shadow Normal Bias` first, then `Shadow Bias`, to control acne.

### Limitations

- A point light consumes six additional-shadow tiles. The default limit of 16 additional shadowed lights gives a maximum of 96 tiles.
- The additional shadow matrix array is `MAX_ADDITIONAL_SHADOW_TILES` (`16 * 6`) matrices, i.e. 96 `float4x4` values or about **6 KB of fragment uniform data**. Desktop targets handle this, but GLES3's minimum fragment uniform budget is much smaller. If the shader fails to compile or lights lose their shadows on GLES3, lower `MaxShadowedAdditionalLightsCount` or add a compile-time cap for that platform.
- If `ComputePointShadowMatricesAndCullingPrimitives` fails for a face, that face's tile is cleared and its matrix is zeroed. `metadata.w` carries the valid-face bitmask, so the shader returns "no shadow" for that face instead of sampling last frame's content.
- The atlas resolution is shared with spot lights. Raise `Additional/Atlas Size` when several point lights cast shadows.
- Per-face resolution is lower than the directional atlas, because one point light uses six tiles. Fewer shadowed point lights or a bigger atlas improves the result.
- Additional-light shadows require `Additional Lights` to be enabled (`Per Pixel` mode). Tiled lighting is supported.

### Troubleshooting

- **No shadow:** confirm `Additional/Point` is enabled, the light is `Realtime`, `Shadow Type` is not `No Shadows`, and the light range contains both the receiver and a shadow caster.
- **Shadow acne:** increase the light's `Shadow Normal Bias` first, then `Shadow Bias`.
- **Detached shadows:** reduce `Shadow Normal Bias` and `Shadow Bias`.
- **Seams between faces:** raise `Additional/Atlas Size` or reduce the number of shadowed point lights.
