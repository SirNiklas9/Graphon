package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:mem"
import "core:c"

// True GPU grid renderer — one draw call for the entire grid
GPUGrid :: struct {
	shader:     rl.Shader,
	fg_tex:     rl.Texture2D,
	bg_tex:     rl.Texture2D,
	char_tex:   rl.Texture2D,
	fg_data:    []u8,
	bg_data:    []u8,
	char_data:  []u8,
	cols:       int,
	rows:       int,
	enabled:    bool,

	// Uniform locations
	cell_fg_loc:     i32,
	cell_bg_loc:     i32,
	cell_char_loc:   i32,
	font_atlas_loc:  i32,
	resolution_loc:  i32,
	grid_size_loc:   i32,
	cell_size_loc:   i32,
	glyph_rects_loc: i32,
	atlas_size_loc:  i32,
}

gpu_grid_create :: proc(cols, rows: int) -> GPUGrid {
	gg := GPUGrid{
		cols = cols,
		rows = rows,
		enabled = false,
	}

	// Load the grid rendering shader
	gg.shader = rl.LoadShader(nil, "assets/gpu_grid.glsl")

	// Check if shader loaded (id 0 = Raylib default, not our shader)
	if gg.shader.id <= 0 {
		rl.TraceLog(.WARNING, "GPU grid shader failed to load")
		return gg
	}
	rl.TraceLog(.INFO, "GPU grid shader loaded (program ID: %d)", gg.shader.id)

	// Get uniform locations
	gg.cell_fg_loc = rl.GetShaderLocation(gg.shader, "texture0")
	gg.cell_bg_loc = rl.GetShaderLocation(gg.shader, "cellBG")
	gg.cell_char_loc = rl.GetShaderLocation(gg.shader, "cellChar")
	gg.font_atlas_loc = rl.GetShaderLocation(gg.shader, "fontAtlas")
	gg.resolution_loc = rl.GetShaderLocation(gg.shader, "resolution")
	gg.grid_size_loc = rl.GetShaderLocation(gg.shader, "gridSize")
	gg.cell_size_loc = rl.GetShaderLocation(gg.shader, "cellSize")
	gg.glyph_rects_loc = rl.GetShaderLocation(gg.shader, "glyphRects[0]")
	gg.atlas_size_loc = rl.GetShaderLocation(gg.shader, "atlasSize")

	// Allocate CPU-side pixel buffers
	gpu_grid_alloc_buffers(&gg, cols, rows)

	gg.enabled = true
	return gg
}

gpu_grid_alloc_buffers :: proc(gg: ^GPUGrid, cols, rows: int) {
	size := cols * rows * 4 // RGBA
	char_size := cols * rows // single channel

	gg.fg_data = make([]u8, size)
	gg.bg_data = make([]u8, size)
	gg.char_data = make([]u8, char_size)

	// Create textures
	fg_img := rl.Image{
		data = raw_data(gg.fg_data),
		width = i32(cols), height = i32(rows),
		mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8,
	}
	bg_img := rl.Image{
		data = raw_data(gg.bg_data),
		width = i32(cols), height = i32(rows),
		mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8,
	}
	char_img := rl.Image{
		data = raw_data(gg.char_data),
		width = i32(cols), height = i32(rows),
		mipmaps = 1, format = .UNCOMPRESSED_GRAYSCALE,
	}

	gg.fg_tex = rl.LoadTextureFromImage(fg_img)
	gg.bg_tex = rl.LoadTextureFromImage(bg_img)
	gg.char_tex = rl.LoadTextureFromImage(char_img)

	// Nearest filter — no interpolation between cells
	rl.SetTextureFilter(gg.fg_tex, .POINT)
	rl.SetTextureFilter(gg.bg_tex, .POINT)
	rl.SetTextureFilter(gg.char_tex, .POINT)
}

gpu_grid_destroy :: proc(gg: ^GPUGrid) {
	if gg.enabled {
		rl.UnloadTexture(gg.fg_tex)
		rl.UnloadTexture(gg.bg_tex)
		rl.UnloadTexture(gg.char_tex)
		delete(gg.fg_data)
		delete(gg.bg_data)
		delete(gg.char_data)
	}
	if gg.shader.id != 0 {
		rl.UnloadShader(gg.shader)
	}
}

gpu_grid_resize :: proc(gg: ^GPUGrid, cols, rows: int) {
	if !gg.enabled do return

	rl.UnloadTexture(gg.fg_tex)
	rl.UnloadTexture(gg.bg_tex)
	rl.UnloadTexture(gg.char_tex)
	delete(gg.fg_data)
	delete(gg.bg_data)
	delete(gg.char_data)

	gg.cols = cols
	gg.rows = rows
	gpu_grid_alloc_buffers(gg, cols, rows)
}

// Build a character index lookup: rune → 0-31 index
char_to_index :: proc(ch: rune) -> u8 {
	chars := ALL_CODEPOINTS
	for i in 0 ..< 32 {
		if chars[i] == ch do return u8(i)
	}
	return 0 // default to full block
}

// Upload the current Grafel buffer to GPU textures
gpu_grid_upload :: proc(gg: ^GPUGrid, grid: ^Grid) {
	if !gg.enabled do return

	cols := min(gg.cols, grid.cols)
	rows := min(gg.rows, grid.rows)

	for row in 0 ..< rows {
		for col in 0 ..< cols {
			g := grid.cells[row * grid.cols + col]
			idx := row * gg.cols + col
			px := idx * 4

			// FG color
			gg.fg_data[px + 0] = g.fg[0]
			gg.fg_data[px + 1] = g.fg[1]
			gg.fg_data[px + 2] = g.fg[2]
			gg.fg_data[px + 3] = g.fg[3]

			// BG color
			gg.bg_data[px + 0] = g.bg[0]
			gg.bg_data[px + 1] = g.bg[1]
			gg.bg_data[px + 2] = g.bg[2]
			gg.bg_data[px + 3] = g.bg[3]

			// Character index
			gg.char_data[idx] = char_to_index(g.char)
		}
	}

	// Update GPU textures
	rl.UpdateTexture(gg.fg_tex, raw_data(gg.fg_data))
	rl.UpdateTexture(gg.bg_tex, raw_data(gg.bg_data))
	rl.UpdateTexture(gg.char_tex, raw_data(gg.char_data))
}

// Render the entire grid in one draw call
gpu_grid_render :: proc(gg: ^GPUGrid, grid: ^Grid, font: rl.Font) {
	if !gg.enabled do return

	// Set resolution uniform
	res := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	rl.SetShaderValue(gg.shader, gg.resolution_loc, &res, .VEC2)

	// Set grid size
	gs := [2]f32{f32(grid.cols), f32(grid.rows)}
	rl.SetShaderValue(gg.shader, gg.grid_size_loc, &gs, .VEC2)

	// Set cell size
	cs := [2]f32{grid.cell_w, grid.cell_h}
	rl.SetShaderValue(gg.shader, gg.cell_size_loc, &cs, .VEC2)

	// Set atlas size
	as := [2]f32{f32(font.texture.width), f32(font.texture.height)}
	rl.SetShaderValue(gg.shader, gg.atlas_size_loc, &as, .VEC2)

	// Upload glyph rectangles
	chars := ALL_CODEPOINTS
	glyph_rects: [32][4]f32
	for i in 0 ..< 32 {
		gi := rl.GetGlyphIndex(font, chars[i])
		rec := font.recs[gi]
		glyph_rects[i] = {rec.x, rec.y, rec.width, rec.height}
	}
	for i in 0 ..< 32 {
		loc := rl.GetShaderLocation(gg.shader, rl.TextFormat("glyphRects[%d]", i32(i)))
		rl.SetShaderValue(gg.shader, loc, &glyph_rects[i], .VEC4)
	}

	// Use the fg texture as the "base" texture for DrawTexturePro
	// Then bind the rest as additional texture units
	bg_unit: i32 = 1
	char_unit: i32 = 2
	atlas_unit: i32 = 3

	rl.SetShaderValue(gg.shader, gg.cell_bg_loc, &bg_unit, .INT)
	rl.SetShaderValue(gg.shader, gg.cell_char_loc, &char_unit, .INT)
	rl.SetShaderValue(gg.shader, gg.font_atlas_loc, &atlas_unit, .INT)

	// cellFG goes to unit 0 (default texture slot used by DrawTexturePro)
	fg_unit: i32 = 0
	rl.SetShaderValue(gg.shader, gg.cell_fg_loc, &fg_unit, .INT)

	// Flush any pending Raylib draws before we mess with texture units
	rlgl.DrawRenderBatchActive()

	// Bind additional textures to their units
	rlgl.ActiveTextureSlot(bg_unit)
	rlgl.EnableTexture(gg.bg_tex.id)
	rlgl.ActiveTextureSlot(char_unit)
	rlgl.EnableTexture(gg.char_tex.id)
	rlgl.ActiveTextureSlot(atlas_unit)
	rlgl.EnableTexture(font.texture.id)
	rlgl.ActiveTextureSlot(0)

	// Draw fg texture fullscreen — the shader reads cell data and renders the grid
	rl.BeginShaderMode(gg.shader)
	src := rl.Rectangle{0, 0, f32(gg.fg_tex.width), f32(gg.fg_tex.height)}
	dst := rl.Rectangle{0, 0, res[0], res[1]}
	rl.DrawTexturePro(gg.fg_tex, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()

	// Flush then clean up texture bindings
	rlgl.DrawRenderBatchActive()
	for unit in 1 ..= 3 {
		rlgl.ActiveTextureSlot(i32(unit))
		rlgl.DisableTexture()
	}
	rlgl.ActiveTextureSlot(0)
}
