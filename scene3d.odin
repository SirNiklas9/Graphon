package main

import rl "vendor:raylib"
import "core:math"

// GPU 3D scene renderer — uses Raylib's native 3D pipeline to render models,
// then captures the output for the Grafel glyph shader
Scene3D :: struct {
	target:  rl.RenderTexture2D,
	cols:    int,
	rows:    int,
	enabled: bool,
}

scene3d_create :: proc(cols, rows: int) -> Scene3D {
	// Cap resolution like compute pipeline
	MAX_PIXELS :: 640 * 360
	c, r := cols, rows
	total := c * r
	if total > MAX_PIXELS {
		ratio := f32(MAX_PIXELS) / f32(total)
		scale := math.sqrt(ratio)
		c = max(int(f32(c) * scale), 1)
		r = max(int(f32(r) * scale), 1)
	}

	target := rl.LoadRenderTexture(i32(c), i32(r))
	return Scene3D{target = target, cols = c, rows = r, enabled = true}
}

scene3d_destroy :: proc(s: ^Scene3D) {
	if s.enabled {
		rl.UnloadRenderTexture(s.target)
	}
}

scene3d_resize :: proc(s: ^Scene3D, cols, rows: int) {
	if s.enabled {
		rl.UnloadRenderTexture(s.target)
	}
	s^ = scene3d_create(cols, rows)
}

// Render a full 3D scene with models using Raylib's GPU pipeline
scene3d_render :: proc(
	s: ^Scene3D,
	cam: ^Camera,
	models: []Scene3DObject,
	time: f32,
) {
	if !s.enabled do return

	rl.BeginTextureMode(s.target)
	rl.ClearBackground({20, 20, 25, 255})

	rl.BeginMode3D(cam.rl_cam)

	// Ground plane
	rl.DrawPlane({0, 0, 0}, {40, 40}, {100, 100, 100, 255})

	// Checkerboard on ground
	for gz: i32 = -10; gz < 10; gz += 1 {
		for gx: i32 = -10; gx < 10; gx += 1 {
			if (gx + gz) % 2 == 0 {
				rl.DrawPlane(
					{f32(gx) * 2 + 1, 0.01, f32(gz) * 2 + 1},
					{2, 2},
					{70, 70, 70, 255},
				)
			}
		}
	}

	// Render all scene objects
	for &obj in models {
		if !obj.model.loaded do continue

		pos := obj.position
		rot_y := obj.rotation_y
		if obj.auto_rotate {
			rot_y += time * obj.rotate_speed
		}

		rl.DrawModelEx(
			obj.model.model,
			pos,
			{0, 1, 0},          // rotation axis
			rot_y * 57.2958,     // radians to degrees
			{obj.scale, obj.scale, obj.scale},
			obj.tint,
		)
	}

	// Light indicator sphere
	light_pos := rl.Vector3{math.cos(time * 0.7) * 8, 6, math.sin(time * 0.7) * 8}
	rl.DrawSphere(light_pos, 0.3, {255, 200, 100, 255})

	// Pillars
	pillar_colors := [4]rl.Color{{50, 200, 80, 255}, {80, 100, 220, 255}, {200, 80, 180, 255}, {80, 200, 200, 255}}
	pillar_pos := [4]rl.Vector3{{-8, 3, -5}, {8, 3, -5}, {-8, 3, 5}, {8, 3, 5}}
	for i in 0 ..< 4 {
		rl.DrawCylinder(pillar_pos[i], 0.6, 0.6, 6, 12, pillar_colors[i])
	}

	rl.EndMode3D()
	rl.EndTextureMode()
}

// Object in a 3D scene
Scene3DObject :: struct {
	model:        ^GraphonModel,
	position:     rl.Vector3,
	scale:        f32,
	rotation_y:   f32,
	auto_rotate:  bool,
	rotate_speed: f32,
	tint:         rl.Color,
}
