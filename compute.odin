package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// GPU compute pipeline — generates cell data entirely on GPU
// Uses fragment shaders rendering to a grid-sized texture (each pixel = one cell)
ComputeMode :: enum {
	Random,
	Scene,
}

COMPUTE_MODE_COUNT :: 2

ComputePipeline :: struct {
	random_shader: rl.Shader,
	scene_shader:  rl.Shader,
	target:        rl.RenderTexture2D,
	cols:          int,
	rows:          int,
	active_mode:   ComputeMode,
	enabled:       bool,

	// Uniform locations
	random_time_loc:     i32,
	random_gridsize_loc: i32,
	scene_time_loc:      i32,
	scene_gridsize_loc:  i32,
	scene_res_loc:       i32,
	scene_cellsize_loc:  i32,
}

compute_create :: proc(cols, rows: int) -> ComputePipeline {
	cp := ComputePipeline{
		cols = cols,
		rows = rows,
		active_mode = .Scene,
		enabled = false,
	}

	cp.random_shader = rl.LoadShader(nil, "assets/compute_random.glsl")
	cp.scene_shader = rl.LoadShader(nil, "assets/compute_scene.glsl")

	if cp.random_shader.id == 0 || cp.scene_shader.id == 0 {
		rl.TraceLog(.WARNING, "Compute shaders failed to load")
		return cp
	}

	cp.random_time_loc = rl.GetShaderLocation(cp.random_shader, "time")
	cp.random_gridsize_loc = rl.GetShaderLocation(cp.random_shader, "gridSize")
	cp.scene_time_loc = rl.GetShaderLocation(cp.scene_shader, "time")
	cp.scene_gridsize_loc = rl.GetShaderLocation(cp.scene_shader, "gridSize")
	cp.scene_res_loc = rl.GetShaderLocation(cp.scene_shader, "resolution")
	cp.scene_cellsize_loc = rl.GetShaderLocation(cp.scene_shader, "cellSize")

	// RenderTexture at grid resolution — each pixel = one cell
	cp.target = rl.LoadRenderTexture(i32(cols), i32(rows))
	rl.SetTextureFilter(cp.target.texture, .POINT)

	cp.enabled = true
	return cp
}

compute_destroy :: proc(cp: ^ComputePipeline) {
	if cp.enabled {
		rl.UnloadRenderTexture(cp.target)
	}
	if cp.random_shader.id != 0 { rl.UnloadShader(cp.random_shader) }
	if cp.scene_shader.id != 0 { rl.UnloadShader(cp.scene_shader) }
}

compute_resize :: proc(cp: ^ComputePipeline, cols, rows: int) {
	if !cp.enabled do return
	rl.UnloadRenderTexture(cp.target)
	cp.cols = cols
	cp.rows = rows
	cp.target = rl.LoadRenderTexture(i32(cols), i32(rows))
	rl.SetTextureFilter(cp.target.texture, .POINT)
}

// Run the compute shader — generates cell colors into the target texture
compute_run :: proc(cp: ^ComputePipeline, time_val: f32, grid: ^Grid) {
	if !cp.enabled do return

	time := time_val
	gs := [2]f32{f32(cp.cols), f32(cp.rows)}

	shader: rl.Shader
	switch cp.active_mode {
	case .Random:
		shader = cp.random_shader
		rl.SetShaderValue(shader, cp.random_time_loc, &time, .FLOAT)
		rl.SetShaderValue(shader, cp.random_gridsize_loc, &gs, .VEC2)
	case .Scene:
		shader = cp.scene_shader
		rl.SetShaderValue(shader, cp.scene_time_loc, &time, .FLOAT)
		rl.SetShaderValue(shader, cp.scene_gridsize_loc, &gs, .VEC2)
		res := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.SetShaderValue(shader, cp.scene_res_loc, &res, .VEC2)
		cs := [2]f32{grid.cell_w, grid.cell_h}
		rl.SetShaderValue(shader, cp.scene_cellsize_loc, &cs, .VEC2)
	}

	// Render to grid-sized texture using a textured quad for proper UVs
	rl.BeginTextureMode(cp.target)
	rl.ClearBackground(rl.BLACK)
	rl.BeginShaderMode(shader)
	// Use Raylib's default texture (1x1 white) stretched to fill — gives 0-1 UVs
	default_tex := rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	src := rl.Rectangle{0, 0, 1, 1}
	dst := rl.Rectangle{0, 0, f32(cp.cols), f32(cp.rows)}
	rl.DrawTexturePro(default_tex, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()
	rl.EndTextureMode()
}

// Read back computed pixels into the Grafel buffer
// This is still a CPU readback but the generation was GPU
compute_readback :: proc(cp: ^ComputePipeline, grid: ^Grid) {
	if !cp.enabled do return

	img := rl.LoadImageFromTexture(cp.target.texture)
	defer rl.UnloadImage(img)

	cols := min(cp.cols, grid.cols)
	rows := min(cp.rows, grid.rows)

	for row in 0 ..< rows {
		// RenderTexture is flipped in OpenGL
		src_row := cp.rows - 1 - row
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

// Render the compute output directly to screen (bypass CPU readback)
// This is the FAST path — GPU to GPU, no CPU touch
compute_render_direct :: proc(cp: ^ComputePipeline, grid: ^Grid) {
	if !cp.enabled do return

	src := rl.Rectangle{0, 0, f32(cp.target.texture.width), -f32(cp.target.texture.height)}
	dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	rl.DrawTexturePro(cp.target.texture, src, dst, {0, 0}, 0, rl.WHITE)
}

compute_cycle_mode :: proc(cp: ^ComputePipeline) {
	cp.active_mode = ComputeMode((int(cp.active_mode) + 1) % COMPUTE_MODE_COUNT)
}
