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

### Limitations

- A point light consumes six additional-shadow tiles. The default limit of 16 additional shadowed lights gives a maximum of 96 tiles.
- The atlas resolution is shared with spot lights. Raise `Additional/Atlas Size` when several point lights cast shadows.
- Additional-light shadows (spot and point) use a single shadow lookup. The `Soft Shadows` and VSM settings apply to directional shadows; point-light shadows are intentionally crisp. Use the light's bias settings to control acne and peter-panning.
- Additional-light shadows require `Additional Lights` to be enabled (`Per Pixel` mode). Tiled lighting is supported.

### Troubleshooting

- **No shadow:** confirm `Additional/Point` is enabled, the light is `Realtime`, `Shadow Type` is not `No Shadows`, and the light range contains both the receiver and a shadow caster.
- **Shadow acne:** increase the light's `Shadow Normal Bias` first, then `Shadow Bias`.
- **Detached shadows:** reduce `Shadow Normal Bias` and `Shadow Bias`.
- **Seams between faces:** increase `Additional/Atlas Size` or reduce the number of shadowed point lights.
