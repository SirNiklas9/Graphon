package main

import rl "vendor:raylib"

// Runtime configuration — every tunable value in the renderer
Config :: struct {
	// Rendering
	font_size:       i32,
	fidelity:        Fidelity,
	forced_fidelity: bool,

	// Lighting
	ambient:         [3]f32,

	// Fog
	fog_enabled:     bool,
	fog_color:       [3]f32,
	fog_start:       f32,
	fog_end:         f32,

	// Shadows
	shadow_map_size: i32,
	shadow_radius:   f32,    // Ortho coverage radius

	// Post-process
	bloom_intensity: f32,
	bloom_threshold: f32,

	// Sky
	sky_enabled:     bool,

	// Graphon 3D
	edge_threshold:      f32,   // Min brightness diff for edge characters
	density_thresholds:  [4]f32, // Brightness cutoffs: solid, 75%, 50%, 25%
	density_bg_factor:   f32,   // bg = fg * this (0-1)

	// Display
	fps_cap:         i32,
	vsync:           bool,
	fullscreen:      bool,

	// Debug
	show_grid_lines:  bool,
	show_cell_coords: bool,
}

config_default :: proc() -> Config {
	return Config{
		font_size       = 1,
		fidelity        = .ALL,
		forced_fidelity = false,

		ambient         = {0.06, 0.06, 0.1},

		fog_enabled     = true,
		fog_color       = {0.6, 0.7, 0.8},
		fog_start       = 40,
		fog_end         = 120,

		shadow_map_size = 4096,
		shadow_radius   = 15,

		bloom_intensity = 0.5,
		bloom_threshold = 0.3,

		sky_enabled     = true,

		edge_threshold     = 0.25,
		density_thresholds = {0.7, 0.45, 0.20, 0.05},
		density_bg_factor  = 0.7,

		fps_cap         = 0,
		vsync           = false,
		fullscreen      = false,

		show_grid_lines  = false,
		show_cell_coords = false,
	}
}

// Apply config changes that need immediate effect
config_apply :: proc(cfg: ^Config) {
	rl.SetTargetFPS(cfg.fps_cap)
}

// Debug overlay: draw grid lines between cells
debug_grid_lines :: proc(grid: ^Grid, override_cols: int = 0, override_rows: int = 0) {
	cols := override_cols > 0 ? override_cols : grid.cols
	rows := override_rows > 0 ? override_rows : grid.rows
	cw := f32(rl.GetScreenWidth()) / f32(cols)
	ch := f32(rl.GetScreenHeight()) / f32(rows)

	color := rl.Color{60, 60, 60, 100}
	for col in 0 ..= cols {
		x := i32(f32(col) * cw)
		rl.DrawLine(x, 0, x, i32(f32(rows) * ch), color)
	}
	for row in 0 ..= rows {
		y := i32(f32(row) * ch)
		rl.DrawLine(0, y, i32(f32(cols) * cw), y, color)
	}
}

// Debug overlay: show cell coordinates
debug_cell_coords :: proc(grid: ^Grid, font: rl.Font, override_cols: int = 0, override_rows: int = 0) {
	cols := override_cols > 0 ? override_cols : grid.cols
	rows := override_rows > 0 ? override_rows : grid.rows
	cw := f32(rl.GetScreenWidth()) / f32(cols)
	ch := f32(rl.GetScreenHeight()) / f32(rows)

	if cw < 30 do return
	for row in 0 ..< min(rows, 20) {
		for col in 0 ..< min(cols, 20) {
			x := f32(col) * cw + 1
			y := f32(row) * ch + 1
			rl.DrawTextEx(font, rl.TextFormat("%d,%d", i32(col), i32(row)),
				{x, y}, f32(grid.font_size) * 0.4, 0, {255, 255, 0, 150})
		}
	}
}

// Take a screenshot
export_screenshot :: proc(path: cstring = "screenshot.png") {
	rl.TakeScreenshot(path)
}
