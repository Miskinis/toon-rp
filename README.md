# Toon RP

For relevant documentation, please visit [the repository](https://github.com/Delt06/toon-rp).

## Point Light Shadows

Point lights can cast real-time shadows into the same additional-light shadow atlas used by spot lights. The feature is opt-in:

1. In the pipeline asset, enable `Shadows/Shadow Maps/Additional`.
2. Enable `Point`.
3. On each point light, set `Shadow Type` to `Hard Shadows` or `Soft Shadows` and keep `Shadow Strength` above `0`.
4. Make sure the light is `Realtime`. Baked and mixed lights do not cast real-time shadows.

### How it works

A point light is rendered into six atlas tiles, one per cubemap face (`+X`, `-X`, `+Y`, `-Y`, `+Z`, `-Z`). The view and projection matrices come from `CullingResults.ComputePointShadowMatricesAndCullingPrimitives`. At shading time, the face is selected from the dominant axis of the light-to-fragment direction, and the matching atlas tile is sampled.

Spot and point lights can be mixed freely. Each light keeps its own atlas tile range.

Point and spot shadow attenuation is passed through the same toon shadow ramp and pattern as the directional shadows.

### Quality settings

Point shadows share the additional-light atlas and use the same VSM path as directional shadows: a two-channel moments atlas, a Gaussian blur, and the same light-bleeding reduction and precision compensation.

- Set `Additional/Atlas Size` to `2048` or `4096`. A point light consumes six tiles, so the per-face resolution is `atlasSize / ceil(sqrt(totalTiles))`.
- The additional blur is clamped to each atlas tile, so the kernel never samples a neighbouring cubemap face.
- `Blur` (`Box`, `Gaussian Low Quality`, `Gaussian High Quality`), `Blur Scatter`, `Blur Early Bail`, `Light Bleeding Reduction`, `VSM Precision`, and `Precision Compensation` apply to both shadow atlases.
- `Soft Shadows/Spread` only affects the non-VSM PCF path. With VSM, shadow softness comes from `Blur Scatter`.
- Use the light's `Shadow Normal Bias` first, then `Shadow Bias`, to control acne.

### Limitations

- A point light consumes six additional-shadow tiles. The default limit of 16 additional shadowed lights gives a maximum of 96 tiles.
- The additional shadow matrix array grows to 96 entries; on GLES3 the fragment uniform budget may require a lower `MaxShadowedAdditionalLightsCount`.
- The atlas resolution is shared with spot lights. Raise `Additional/Atlas Size` when several point lights cast shadows.
- Per-face resolution is lower than the directional atlas, because one point light uses six tiles. Fewer shadowed point lights or a bigger atlas improves the result.
- Additional-light shadows require `Additional Lights` to be enabled (`Per Pixel` mode). Tiled lighting is supported.

### Troubleshooting

- **No shadow:** confirm `Additional/Point` is enabled, the light is `Realtime`, `Shadow Type` is not `No Shadows`, and the light range contains both the receiver and a shadow caster.
- **Shadow acne:** increase the light's `Shadow Normal Bias` first, then `Shadow Bias`.
- **Detached shadows:** reduce `Shadow Normal Bias` and `Shadow Bias`.
- **Seams between faces:** raise `Additional/Atlas Size` or reduce the number of shadowed point lights.
