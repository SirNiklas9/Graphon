package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"

// GPU compute pipeline — one shader per demo mode
// Each shader generates cell colors entirely on GPU
ComputePipeline :: struct {
	shaders:  [6]rl.Shader, // one per demo mode (0-5)
	target:   rl.RenderTexture2D,
	cols:     int,
	rows:     int,
	enabled:  bool,

	// Common uniform locations per shader
	time_locs:     [6]i32,
	gridsize_locs: [6]i32,
	extra_locs:    [6]i32, // mode-specific (blendMode for solver, etc.)

	// Cached locations for 3D mode
	cam_pos_loc:    i32,
	cam_target_loc: i32,
	screen_res_loc: i32,
	// Cached locations for scene mode
	scene_res_loc:  i32,
	scene_cs_loc:   i32,
}

COMPUTE_SHADER_PATHS :: [6]cstring{
	"assets/compute_random.glsl",     // 0: Random
	"assets/compute_solver.glsl",     // 1: Solver
	"assets/compute_primitives.glsl", // 2: Primitives
	"assets/compute_3d.glsl",         // 3: 3D
	"assets/compute_layers.glsl",     // 4: Layers
	"assets/compute_scene.glsl",      // 5: Compute
}

compute_create :: proc(cols, rows: int) -> ComputePipeline {
	cp := ComputePipeline{
		cols = cols,
		rows = rows,
		enabled = false,
	}

	all_loaded := true
	paths := COMPUTE_SHADER_PATHS
	for i in 0 ..< 6 {
		cp.shaders[i] = rl.LoadShader(nil, paths[i])
		if cp.shaders[i].id == 0 {
			rl.TraceLog(.WARNING, "Compute shader %d failed to load", i32(i))
			all_loaded = false
		} else {
			cp.time_locs[i] = rl.GetShaderLocation(cp.shaders[i], "time")
			cp.gridsize_locs[i] = rl.GetShaderLocation(cp.shaders[i], "gridSize")
			cp.extra_locs[i] = rl.GetShaderLocation(cp.shaders[i], "blendMode")
		}
	}

	// Cap initial resolution
	total := cols * rows
	if total > COMPUTE_MAX_PIXELS {
		ratio := f32(COMPUTE_MAX_PIXELS) / f32(total)
		scale := math.sqrt(ratio)
		cp.cols = max(int(f32(cols) * scale), 1)
		cp.rows = max(int(f32(rows) * scale), 1)
	}

	cp.target = rl.LoadRenderTexture(i32(cp.cols), i32(cp.rows))
	rl.SetTextureFilter(cp.target.texture, .POINT)

	// Cache mode-specific locations
	if cp.shaders[3].id != 0 {
		cp.cam_pos_loc = rl.GetShaderLocation(cp.shaders[3], "camPos")
		cp.cam_target_loc = rl.GetShaderLocation(cp.shaders[3], "camTarget")
		cp.screen_res_loc = rl.GetShaderLocation(cp.shaders[3], "screenRes")
	}
	if cp.shaders[5].id != 0 {
		cp.scene_res_loc = rl.GetShaderLocation(cp.shaders[5], "resolution")
		cp.scene_cs_loc = rl.GetShaderLocation(cp.shaders[5], "cellSize")
	}

	cp.enabled = all_loaded
	return cp
}

compute_destroy :: proc(cp: ^ComputePipeline) {
	if cp.target.id != 0 {
		rl.UnloadRenderTexture(cp.target)
	}
	for i in 0 ..< 6 {
		if cp.shaders[i].id != 0 { rl.UnloadShader(cp.shaders[i]) }
	}
}

// Max compute resolution — raymarching at full grid res is too expensive
COMPUTE_MAX_PIXELS :: 640 * 360

compute_resize :: proc(cp: ^ComputePipeline, cols, rows: int) {
	if cp.target.id != 0 {
		rl.UnloadRenderTexture(cp.target)
	}

	// Cap resolution while maintaining aspect ratio
	total := cols * rows
	if total > COMPUTE_MAX_PIXELS {
		ratio := f32(COMPUTE_MAX_PIXELS) / f32(total)
		scale := math.sqrt(ratio)
		cp.cols = max(int(f32(cols) * scale), 1)
		cp.rows = max(int(f32(rows) * scale), 1)
	} else {
		cp.cols = cols
		cp.rows = rows
	}

	cp.target = rl.LoadRenderTexture(i32(cp.cols), i32(cp.rows))
	rl.SetTextureFilter(cp.target.texture, .POINT)
}

// Run compute shader for a specific demo mode
compute_run :: proc(cp: ^ComputePipeline, demo_mode: int, time_val: f32, grid: ^Grid, blend_mode: int = 0, cam: ^Camera = nil) {
	if !cp.enabled do return
	if demo_mode < 0 || demo_mode >= 6 do return

	shader := cp.shaders[demo_mode]
	if shader.id == 0 do return

	time := time_val
	gs := [2]f32{f32(cp.cols), f32(cp.rows)}

	rl.SetShaderValue(shader, cp.time_locs[demo_mode], &time, .FLOAT)
	rl.SetShaderValue(shader, cp.gridsize_locs[demo_mode], &gs, .VEC2)

	// Mode-specific uniforms
	if demo_mode == 1 { // solver blend mode
		bm := i32(blend_mode)
		rl.SetShaderValue(shader, cp.extra_locs[demo_mode], &bm, .INT)
	}
	if demo_mode == 3 && cam != nil {
		pos := cam.rl_cam.position
		tgt := cam.rl_cam.target
		res := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.SetShaderValue(shader, cp.cam_pos_loc, &pos, .VEC3)
		rl.SetShaderValue(shader, cp.cam_target_loc, &tgt, .VEC3)
		rl.SetShaderValue(shader, cp.screen_res_loc, &res, .VEC2)
	}
	if demo_mode == 5 {
		res := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		cs := [2]f32{grid.cell_w, grid.cell_h}
		rl.SetShaderValue(shader, cp.scene_res_loc, &res, .VEC2)
		rl.SetShaderValue(shader, cp.scene_cs_loc, &cs, .VEC2)
	}

	// Render to grid-sized texture
	rl.BeginTextureMode(cp.target)
	rl.ClearBackground(rl.BLACK)
	rl.BeginShaderMode(shader)
	default_tex := rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	src := rl.Rectangle{0, 0, 1, 1}
	dst := rl.Rectangle{0, 0, f32(cp.cols), f32(cp.rows)}
	rl.DrawTexturePro(default_tex, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
}

// Read back compute output into the Grafel buffer (for GPU grid glyph rendering)
compute_readback :: proc(cp: ^ComputePipeline, grid: ^Grid) {
	if !cp.enabled do return

	img := rl.LoadImageFromTexture(cp.target.texture)
	defer rl.UnloadImage(img)

	cols := min(cp.cols, grid.cols)
	rows := min(cp.rows, grid.rows)

	for row in 0 ..< rows {
		src_row := cp.rows - 1 - row // RenderTexture Y flip
		for col in 0 ..< cols {
			c := rl.GetImageColor(img, i32(col), i32(src_row))
			grid.cells[row * grid.cols + col] = Grafel{
				char = '█',
				fg   = {c.r, c.g, c.b, 255},
				bg   = {c.r, c.g, c.b, 255},
			}
		}
	}
}

// Render compute output directly to screen — GPU to GPU
compute_render_direct :: proc(cp: ^ComputePipeline, grid: ^Grid) {
	if !cp.enabled do return
	// Disable alpha blending — compute textures store char index in alpha, not transparency
	src := rl.Rectangle{0, 0, f32(cp.target.texture.width), -f32(cp.target.texture.height)}
	dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	rl.DrawTexturePro(cp.target.texture, src, dst, {0, 0}, 0, rl.WHITE)
}
