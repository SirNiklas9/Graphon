package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// GPU grid renderer — single texture, one draw call
// Each pixel in the data texture = one cell's fg color
// The shader maps screen pixels to cells and samples the color
GPUGrid :: struct {
	shader:     rl.Shader,
	color_tex:  rl.Texture2D,
	color_data: []u8,
	cols:       int,
	rows:       int,
	enabled:    bool,

	// Uniform locations
	resolution_loc: i32,
	grid_size_loc:  i32,
	cell_size_loc:  i32,
}

gpu_grid_create :: proc(cols, rows: int) -> GPUGrid {
	gg := GPUGrid{
		cols = cols,
		rows = rows,
		enabled = false,
	}

	gg.shader = rl.LoadShader(nil, "assets/gpu_simple.glsl")
	if gg.shader.id == 0 {
		rl.TraceLog(.WARNING, "GPU simple shader failed to load")
		return gg
	}

	gg.resolution_loc = rl.GetShaderLocation(gg.shader, "resolution")
	gg.grid_size_loc = rl.GetShaderLocation(gg.shader, "gridSize")
	gg.cell_size_loc = rl.GetShaderLocation(gg.shader, "cellSize")

	gpu_grid_alloc(&gg, cols, rows)
	gg.enabled = true
	return gg
}

gpu_grid_alloc :: proc(gg: ^GPUGrid, cols, rows: int) {
	gg.cols = cols
	gg.rows = rows
	gg.color_data = make([]u8, cols * rows * 4)

	// Create RGBA texture at grid resolution
	img := rl.Image{
		data = raw_data(gg.color_data),
		width = i32(cols), height = i32(rows),
		mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8,
	}
	gg.color_tex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(gg.color_tex, .POINT)
}

gpu_grid_destroy :: proc(gg: ^GPUGrid) {
	if gg.enabled {
		rl.UnloadTexture(gg.color_tex)
		delete(gg.color_data)
	}
	if gg.shader.id != 0 {
		rl.UnloadShader(gg.shader)
	}
}

gpu_grid_resize :: proc(gg: ^GPUGrid, cols, rows: int) {
	if !gg.enabled do return
	rl.UnloadTexture(gg.color_tex)
	delete(gg.color_data)
	gpu_grid_alloc(gg, cols, rows)
}

// Upload Grafel buffer fg colors to the GPU texture
gpu_grid_upload :: proc(gg: ^GPUGrid, grid: ^Grid) {
	if !gg.enabled do return

	cols := min(gg.cols, grid.cols)
	rows := min(gg.rows, grid.rows)

	for row in 0 ..< rows {
		for col in 0 ..< cols {
			g := grid.cells[row * grid.cols + col]
			px := (row * gg.cols + col) * 4
			gg.color_data[px + 0] = g.fg[0]
			gg.color_data[px + 1] = g.fg[1]
			gg.color_data[px + 2] = g.fg[2]
			gg.color_data[px + 3] = 255
		}
	}

	rl.UpdateTexture(gg.color_tex, raw_data(gg.color_data))
}

// Render the entire grid in one draw call
gpu_grid_render :: proc(gg: ^GPUGrid, grid: ^Grid, font: rl.Font) {
	if !gg.enabled do return

	// Set uniforms
	res := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	rl.SetShaderValue(gg.shader, gg.resolution_loc, &res, .VEC2)

	gs := [2]f32{f32(grid.cols), f32(grid.rows)}
	rl.SetShaderValue(gg.shader, gg.grid_size_loc, &gs, .VEC2)

	cs := [2]f32{grid.cell_w, grid.cell_h}
	rl.SetShaderValue(gg.shader, gg.cell_size_loc, &cs, .VEC2)

	// Draw the color texture fullscreen with the shader
	// DrawTexturePro stretches the texture and gives 0-1 UVs via fragTexCoord
	rl.BeginShaderMode(gg.shader)
	src := rl.Rectangle{0, 0, f32(gg.color_tex.width), f32(gg.color_tex.height)}
	dst := rl.Rectangle{0, 0, res[0], res[1]}
	rl.DrawTexturePro(gg.color_tex, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()
}
