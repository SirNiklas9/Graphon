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
debug_grid_lines :: proc(grid: ^Grid) {
	color := rl.Color{60, 60, 60, 100}
	// Vertical lines
	for col in 0 ..= grid.cols {
		x := i32(f32(col) * grid.cell_w)
		rl.DrawLine(x, 0, x, i32(f32(grid.rows) * grid.cell_h), color)
	}
	// Horizontal lines
	for row in 0 ..= grid.rows {
		y := i32(f32(row) * grid.cell_h)
		rl.DrawLine(0, y, i32(f32(grid.cols) * grid.cell_w), y, color)
	}
}

// Debug overlay: show cell coordinates at each cell
debug_cell_coords :: proc(grid: ^Grid, font: rl.Font) {
	if grid.cell_w < 30 do return // too small to show coords
	for row in 0 ..< min(grid.rows, 20) {
		for col in 0 ..< min(grid.cols, 20) {
			x := f32(col) * grid.cell_w + 1
			y := f32(row) * grid.cell_h + 1
			rl.DrawTextEx(font, rl.TextFormat("%d,%d", i32(col), i32(row)),
				{x, y}, f32(grid.font_size) * 0.4, 0, {255, 255, 0, 150})
		}
	}
}

// Debug overlay: show depth buffer as grayscale
debug_depth_buffer :: proc(grid: ^Grid, db: ^DepthBuffer) {
	if db == nil do return
	max_depth: f32 = 60

	for row in 0 ..< min(grid.rows, db.rows) {
		for col in 0 ..< min(grid.cols, db.cols) {
			d := db.data[row * db.cols + col]
			if d >= 1e29 do continue // no depth written
			brightness := u8(255 - clamp(d / max_depth * 255, 0, 255))
			grid_set(grid, col, row, Grafel{
				char = '█',
				fg = {brightness, brightness, brightness, 255},
				bg = {brightness, brightness, brightness, 255},
			})
		}
	}
}

// Take a screenshot
export_screenshot :: proc(path: cstring = "screenshot.png") {
	rl.TakeScreenshot(path)
}
