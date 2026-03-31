# Graphon

Real-time rendering engine where Unicode block characters are the pixel primitive.

## What Is It

Graphon renders 3D scenes through **Grafels** — grapheme elements. Like pixels are picture elements and voxels are volume elements, a Grafel is the smallest renderable unit: a Unicode block character cell encoding coverage, foreground color, and background color.

The renderer is not a post-process ASCII filter. Grafels ARE the rendering pipeline — the scene is rasterized through them, not approximated by them after the fact.

## Features

- **Multi-light system** — 4 lights (directional + point), quadratic attenuation
- **Shadow mapping** — 4096x4096 depth buffer, 9x9 PCF, front-face culling
- **Specular** — Blinn-Phong with surface-aware masking
- **Normal mapping** — TBN matrix infrastructure
- **SSAO** — float32 depth texture, gradient-aware sampling
- **ACES tone mapping** + gamma correction (linear workflow)
- **Distance fog** — configurable start/end/color
- **Atmospheric skybox** — procedural sphere with Rayleigh-like scattering
- **Volumes** — 3D fog/tint regions with bounding boxes
- **Particle rendering** — billboarded quads with additive blending
- **Post-process** — bloom, scanlines, chromatic aberration
- **Procedural Grafels** — all 32 block characters rendered mathematically (no font atlas)
- **Fidelity system** — FULL_ONLY / DENSITY / HALF / FRACTIONAL / ALL
- **Texture mapping** — diffuse textures via Material system
- **Config system** — all renderer settings in one runtime-configurable struct

## Tech Stack

- **Odin** — language
- **Raylib** — windowing, GPU, input, model loading
- **GLSL 330** — custom shaders (lighting, shadows, SSAO, sky, Graphon conversion)

## Build

```
odin build . -out:graphon.exe -collection:lib=lib
```

Requires: Odin compiler, MSVC Build Tools, JetBrains Mono NF font in `assets/`.

## License

MIT
