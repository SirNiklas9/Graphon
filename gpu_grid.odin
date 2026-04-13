package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// GPU grid renderer — renders Grafels with block characters via shader
// Two data textures + font atlas = full Graphon rendering in one draw call
GPUGrid :: struct {
	shader:     rl.Shader,
	fg_tex:     rl.Texture2D, // RGBA: fg.r, fg.g, fg.b, char_index
	bg_tex:     rl.Texture2D, // RGBA: bg.r, bg.g, bg.b, 255
	fg_data:    []u8,
	bg_data:    []u8,
	cols:       int,
	rows:       int,
	enabled:    bool,

	// Uniform locations
	bg_loc:           i32,
	atlas_loc:        i32,
	resolution_loc:   i32,
	grid_size_loc:    i32,
	cell_size_loc:    i32,
	atlas_size_loc:   i32,
	fidelity_loc:           i32,
	compute_mode_loc:       i32,
	glyph_rect_locs:        [32]i32,
	cfg_edge_threshold_loc: i32,
	cfg_density_thresh_loc: i32,
	cfg_density_bg_loc:     i32,

	// Cached state — only re-upload when changed
	cached_cols:      int,
	cached_rows:      int,
	cached_font_id:   u32,
	glyphs_uploaded:  bool,
	statics_uploaded: bool,
}

gpu_grid_create :: proc(cols, rows: int) -> GPUGrid {
	gg := GPUGrid{
		cols = cols,
		rows = rows,
		enabled = false,
	}

	gg.shader = rl.LoadShader(nil, "assets/gpu_grid.glsl")
	if gg.shader.id == 0 {
		rl.TraceLog(.WARNING, "GPU grid shader failed to load")
		return gg
	}

	gg.bg_loc = rl.GetShaderLocation(gg.shader, "cellBG")
	gg.atlas_loc = rl.GetShaderLocation(gg.shader, "fontAtlas")
	gg.resolution_loc = rl.GetShaderLocation(gg.shader, "resolution")
	gg.grid_size_loc = rl.GetShaderLocation(gg.shader, "gridSize")
	gg.cell_size_loc = rl.GetShaderLocation(gg.shader, "cellSize")
	gg.atlas_size_loc = rl.GetShaderLocation(gg.shader, "atlasSize")
	gg.fidelity_loc = rl.GetShaderLocation(gg.shader, "fidelityLevel")
	gg.compute_mode_loc = rl.GetShaderLocation(gg.shader, "computeMode")
	gg.cfg_edge_threshold_loc = rl.GetShaderLocation(gg.shader, "cfgEdgeThreshold")
	gg.cfg_density_thresh_loc = rl.GetShaderLocation(gg.shader, "cfgDensityThresholds")
	gg.cfg_density_bg_loc = rl.GetShaderLocation(gg.shader, "cfgDensityBgFactor")

	for i in 0 ..< 32 {
		gg.glyph_rect_locs[i] = rl.GetShaderLocation(gg.shader, rl.TextFormat("glyphRects[%d]", i32(i)))
	}


	gpu_grid_alloc(&gg, cols, rows)
	gg.enabled = true
	return gg
}

gpu_grid_alloc :: proc(gg: ^GPUGrid, cols, rows: int) {
	gg.cols = cols
	gg.rows = rows
	size := cols * rows * 4

	gg.fg_data = make([]u8, size)
	gg.bg_data = make([]u8, size)

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

	gg.fg_tex = rl.LoadTextureFromImage(fg_img)
	gg.bg_tex = rl.LoadTextureFromImage(bg_img)
	rl.SetTextureFilter(gg.fg_tex, .POINT)
	rl.SetTextureFilter(gg.bg_tex, .POINT)
}

gpu_grid_destroy :: proc(gg: ^GPUGrid) {
	if gg.enabled {
		rl.UnloadTexture(gg.fg_tex)
		rl.UnloadTexture(gg.bg_tex)
		delete(gg.fg_data)
		delete(gg.bg_data)
	}
	if gg.shader.id != 0 {
		rl.UnloadShader(gg.shader)
	}
}

gpu_grid_resize :: proc(gg: ^GPUGrid, cols, rows: int) {
	if !gg.enabled do return
	rl.UnloadTexture(gg.fg_tex)
	rl.UnloadTexture(gg.bg_tex)
	delete(gg.fg_data)
	delete(gg.bg_data)
	gpu_grid_alloc(gg, cols, rows)
}

// Rune to character index (0-31)
char_to_index :: proc(ch: rune) -> u8 {
	chars := ALL_CODEPOINTS
	for i in 0 ..< 32 {
		if chars[i] == ch do return u8(i)
	}
	return 0
}

// Upload Grafel buffer to GPU — fg+char packed, bg separate
gpu_grid_upload :: proc(gg: ^GPUGrid, grid: ^Grid) {
	if !gg.enabled do return

	cols := min(gg.cols, grid.cols)
	rows := min(gg.rows, grid.rows)

	for row in 0 ..< rows {
		for col in 0 ..< cols {
			g := grid.cells[row * grid.cols + col]
			px := (row * gg.cols + col) * 4

			// FG + char index packed in alpha
			gg.fg_data[px + 0] = g.fg[0]
			gg.fg_data[px + 1] = g.fg[1]
			gg.fg_data[px + 2] = g.fg[2]
			gg.fg_data[px + 3] = char_to_index(g.char)

			// BG
			gg.bg_data[px + 0] = g.bg[0]
			gg.bg_data[px + 1] = g.bg[1]
			gg.bg_data[px + 2] = g.bg[2]
			gg.bg_data[px + 3] = 255
		}
	}

	rl.UpdateTexture(gg.fg_tex, raw_data(gg.fg_data))
	rl.UpdateTexture(gg.bg_tex, raw_data(gg.bg_data))
}

// Render entire grid in one draw call with glyph rendering
gpu_grid_render :: proc(gg: ^GPUGrid, grid: ^Grid, font: rl.Font, is_compute: bool = false, override_tex: rl.Texture2D = {}, compute_cols: int = 0, compute_rows: int = 0, cfg: ^Config = nil) {
	if !gg.enabled do return

	// Only re-upload static uniforms when grid/font changes
	// Use compute resolution when in compute mode
	effective_cols := is_compute && compute_cols > 0 ? compute_cols : grid.cols
	effective_rows := is_compute && compute_rows > 0 ? compute_rows : grid.rows
	effective_cell_w := f32(rl.GetScreenWidth()) / f32(effective_cols)
	effective_cell_h := f32(rl.GetScreenHeight()) / f32(effective_rows)

	grid_changed := effective_cols != gg.cached_cols || effective_rows != gg.cached_rows
	font_changed := font.texture.id != gg.cached_font_id

	if grid_changed || !gg.statics_uploaded {
		res := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.SetShaderValue(gg.shader, gg.resolution_loc, &res, .VEC2)

		gs := [2]f32{f32(effective_cols), f32(effective_rows)}
		rl.SetShaderValue(gg.shader, gg.grid_size_loc, &gs, .VEC2)

		cs := [2]f32{effective_cell_w, effective_cell_h}
		rl.SetShaderValue(gg.shader, gg.cell_size_loc, &cs, .VEC2)

		gg.cached_cols = effective_cols
		gg.cached_rows = effective_rows
		gg.statics_uploaded = true
	}

	if font_changed || !gg.glyphs_uploaded {
		as := [2]f32{f32(font.texture.width), f32(font.texture.height)}
		rl.SetShaderValue(gg.shader, gg.atlas_size_loc, &as, .VEC2)

		chars := ALL_CODEPOINTS
		for i in 0 ..< 32 {
			gi := rl.GetGlyphIndex(font, chars[i])
			rec := font.recs[gi]
			glyph_rect := [4]f32{rec.x, rec.y, rec.width, rec.height}
			rl.SetShaderValue(gg.shader, gg.glyph_rect_locs[i], &glyph_rect, .VEC4)
		}

		gg.cached_font_id = font.texture.id
		gg.glyphs_uploaded = true
	}

	// These change per-frame
	fid := i32(grid.fidelity)
	rl.SetShaderValue(gg.shader, gg.fidelity_loc, &fid, .INT)

	cm := i32(is_compute ? 1 : 0)
	rl.SetShaderValue(gg.shader, gg.compute_mode_loc, &cm, .INT)

	// Graphon config
	edge_t := cfg != nil ? cfg.edge_threshold : f32(0.25)
	density_t := cfg != nil ? cfg.density_thresholds : [4]f32{0.7, 0.45, 0.20, 0.05}
	bg_f := cfg != nil ? cfg.density_bg_factor : f32(0.7)
	rl.SetShaderValue(gg.shader, gg.cfg_edge_threshold_loc, &edge_t, .FLOAT)
	rl.SetShaderValue(gg.shader, gg.cfg_density_thresh_loc, &density_t, .VEC4)
	rl.SetShaderValue(gg.shader, gg.cfg_density_bg_loc, &bg_f, .FLOAT)

	// Bind bg to unit 1, font atlas to unit 2
	bg_unit: i32 = 1
	atlas_unit: i32 = 2
	rl.SetShaderValue(gg.shader, gg.bg_loc, &bg_unit, .INT)
	rl.SetShaderValue(gg.shader, gg.atlas_loc, &atlas_unit, .INT)

	rlgl.DrawRenderBatchActive()

	rlgl.ActiveTextureSlot(bg_unit)
	rlgl.EnableTexture(gg.bg_tex.id)
	rlgl.ActiveTextureSlot(atlas_unit)
	rlgl.EnableTexture(font.texture.id)
	rlgl.ActiveTextureSlot(0)

	// Choose source texture — either our packed fg texture or an external compute texture
	draw_tex := override_tex.id != 0 ? override_tex : gg.fg_tex

	// Disable alpha blending — compute textures store char index in alpha, not transparency
	if is_compute { rlgl.DisableColorBlend() }

	rl.BeginShaderMode(gg.shader)
	// RenderTextures are Y-flipped in OpenGL — negate height for compute textures
	src_h := f32(draw_tex.height)
	if is_compute { src_h = -src_h }
	src := rl.Rectangle{0, 0, f32(draw_tex.width), src_h}
	dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	rl.DrawTexturePro(draw_tex, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()

	if is_compute { rlgl.EnableColorBlend() }

	rlgl.DrawRenderBatchActive()
	rlgl.ActiveTextureSlot(bg_unit)
	rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(atlas_unit)
	rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(0)
}
