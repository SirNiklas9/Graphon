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
	shader:  rl.Shader,
	light_dir_loc: i32,
	light_color_loc: i32,
	ambient_loc: i32,
	view_pos_loc: i32,
}

scene3d_create :: proc(cols, rows: int) -> Scene3D {
	// Use screen aspect ratio, cap total pixels
	MAX_W :: 960
	MAX_H :: 540
	screen_w := f32(rl.GetScreenWidth())
	screen_h := f32(rl.GetScreenHeight())
	aspect := screen_w / max(screen_h, 1)

	c := min(cols, MAX_W)
	r := int(f32(c) / aspect)
	r = min(r, MAX_H)
	c = int(f32(r) * aspect)
	c = max(c, 1)
	r = max(r, 1)

	target := rl.LoadRenderTexture(i32(c), i32(r))

	// Load lighting shader
	shader := rl.LoadShader("assets/lighting.vs", "assets/lighting.fs")
	light_dir_loc := rl.GetShaderLocation(shader, "lightDir")
	light_color_loc := rl.GetShaderLocation(shader, "lightColor")
	ambient_loc := rl.GetShaderLocation(shader, "ambientColor")
	view_pos_loc := rl.GetShaderLocation(shader, "viewPos")

	// Set matModel and matNormal shader locations so Raylib passes them
	shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocation(shader, "matModel")
	shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL] = rl.GetShaderLocation(shader, "matNormal")

	return Scene3D{
		target = target, cols = c, rows = r, enabled = true,
		shader = shader,
		light_dir_loc = light_dir_loc,
		light_color_loc = light_color_loc,
		ambient_loc = ambient_loc,
		view_pos_loc = view_pos_loc,
	}
}

scene3d_destroy :: proc(s: ^Scene3D) {
	if s.enabled {
		rl.UnloadRenderTexture(s.target)
		if s.shader.id != 0 { rl.UnloadShader(s.shader) }
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

	// Update lighting uniforms
	light_dir := [3]f32{-0.4, -0.8, -0.3}
	light_color := [3]f32{1.0, 0.95, 0.85}
	ambient := [3]f32{0.15, 0.15, 0.2}
	view_pos := [3]f32{cam.rl_cam.position.x, cam.rl_cam.position.y, cam.rl_cam.position.z}
	rl.SetShaderValue(s.shader, s.light_dir_loc, &light_dir, .VEC3)
	rl.SetShaderValue(s.shader, s.light_color_loc, &light_color, .VEC3)
	rl.SetShaderValue(s.shader, s.ambient_loc, &ambient, .VEC3)
	rl.SetShaderValue(s.shader, s.view_pos_loc, &view_pos, .VEC3)

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

	// Render all scene objects with lighting shader
	for &obj in models {
		if !obj.loaded do continue

		// Apply lighting shader to all model materials
		for mi in 0 ..< obj.model.materialCount {
			obj.model.materials[mi].shader = s.shader
		}

		pos := obj.position
		rot_y := obj.rotation_y
		if obj.auto_rotate {
			rot_y += time * obj.rotate_speed
		}

		rl.DrawModelEx(
			obj.model,
			pos,
			{0, 1, 0},
			rot_y * 57.2958,
			{obj.scale, obj.scale, obj.scale},
			obj.tint,
		)
	}

	// Spinning cube — use shader mode for basic primitives too
	rl.BeginShaderMode(s.shader)
	rl.DrawCubeV({0, 2, 0}, {3, 3, 3}, {220, 50, 40, 255})
	// Rotate it by drawing wireframe on top for visual effect
	rl.DrawCubeWiresV({0, 2, 0}, {3.02, 3.02, 3.02}, {180, 30, 20, 255})

	// Light indicator sphere
	light_pos := rl.Vector3{math.cos(time * 0.7) * 8, 6, math.sin(time * 0.7) * 8}
	rl.DrawSphere(light_pos, 0.3, {255, 200, 100, 255})

	// Pillars
	pillar_colors := [4]rl.Color{{50, 200, 80, 255}, {80, 100, 220, 255}, {200, 80, 180, 255}, {80, 200, 200, 255}}
	pillar_pos := [4]rl.Vector3{{-8, 3, -5}, {8, 3, -5}, {-8, 3, 5}, {8, 3, 5}}
	for i in 0 ..< 4 {
		rl.DrawCylinder(pillar_pos[i], 0.6, 0.6, 6, 12, pillar_colors[i])
	}

	rl.EndShaderMode()
	rl.EndMode3D()
	rl.EndTextureMode()
}

// Object in a 3D scene
Scene3DObject :: struct {
	model:        rl.Model,
	loaded:       bool,
	position:     rl.Vector3,
	scale:        f32,
	rotation_y:   f32,
	auto_rotate:  bool,
	rotate_speed: f32,
	tint:         rl.Color,
}
