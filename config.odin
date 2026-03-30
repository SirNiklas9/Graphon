package main

import rl "vendor:raylib"

// Runtime configuration
Config :: struct {
	// Rendering
	font_size:      i32,
	forced_fidelity: bool,
	fidelity:       Fidelity,
	fog_density:    f32,
	bg_color:       [4]u8,
	fog_color:      [4]u8,

	// Display
	fps_cap:        i32,
	vsync:          bool,
	fullscreen:     bool,

	// Debug overlays
	show_grid_lines:  bool,
	show_cell_coords: bool,
	show_fidelity:    bool,
	show_depth:       bool,

	// Export
	screenshot_path: string,
}

config_default :: proc() -> Config {
	return Config{
		font_size      = 20,
		forced_fidelity = false,
		fidelity       = .ALL,
		fog_density    = 1.0,
		bg_color       = {32, 32, 32, 255},
		fog_color      = {32, 32, 32, 255},
		fps_cap        = 60,
		vsync          = false,
		fullscreen     = false,
		show_grid_lines  = false,
		show_cell_coords = false,
		show_fidelity    = false,
		show_depth       = false,
		screenshot_path  = "screenshot.png",
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

// Debug overlay: show cell coordinates at each cell
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
