package main

import rl "vendor:raylib"
import "core:math/rand"
import "core:fmt"
import "core:strings"
import imgui "lib:odin-imgui"
import rlimgui "lib:imgui_impl_raylib"

SCREEN_W     :: 1920
SCREEN_H     :: 1080
INIT_FONT_SZ :: i32(20)
FONT_PATH    :: "assets/JetBrainsMonoNLNerdFont-Regular.ttf"

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Graphon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// ImGui setup
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	rlimgui.init()
	defer rlimgui.shutdown()

	font := load_font(INIT_FONT_SZ)
	defer rl.UnloadFont(font)

	palette := palette_create()
	defer palette_destroy(&palette)
	palette_default(&palette)

	grid: Grid
	grid_init(&grid, SCREEN_W, SCREEN_H, font, INIT_FONT_SZ)
	defer grid_destroy(&grid)

	patterns := pattern_lib_create()
	defer pattern_lib_destroy(&patterns)

	// Define some demo patterns
	pattern_define(&patterns, "heart", {
		".#.#.",
		"#####",
		"#####",
		".###.",
		"..#..",
	}, palette_get(&palette, "red"))

	pattern_define(&patterns, "star", {
		"..#..",
		".###.",
		"#####",
		".###.",
		"..#..",
	}, palette_get(&palette, "yellow"))

	demo_mode: int = 0 // 0=random, 1=solver, 2=primitives
	demo_blend := BlendMode.Normal

	randomize_grid(&grid)

	for !rl.WindowShouldClose() {
		// Font size adjustment
		if rl.IsKeyPressed(.UP) {
			resize_font(&grid, &font, grid.font_size + 2, demo_mode, &palette, demo_blend, &patterns)
		}
		if rl.IsKeyPressed(.DOWN) {
			resize_font(&grid, &font, grid.font_size - 2, demo_mode, &palette, demo_blend, &patterns)
		}
		if rl.IsKeyPressed(.LEFT) {
			resize_font(&grid, &font, grid.font_size - 1, demo_mode, &palette, demo_blend, &patterns)
		}
		if rl.IsKeyPressed(.RIGHT) {
			resize_font(&grid, &font, grid.font_size + 1, demo_mode, &palette, demo_blend, &patterns)
		}

		// Cycle demo mode: 0=random, 1=solver, 2=primitives
		if rl.IsKeyPressed(.TAB) {
			demo_mode = (demo_mode + 1) % 3
			refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
		}

		// Cycle blend mode in solver demo
		if demo_mode == 1 && rl.IsKeyPressed(.B) {
			demo_blend = BlendMode((int(demo_blend) + 1) % 4)
			refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
		}

		// Re-randomize / refresh on SPACE
		if rl.IsKeyPressed(.SPACE) {
			refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Render Grafel grid
		render_grid(&grid, font)

		// ImGui overlay
		rlimgui.begin()

		imgui.SetNextWindowPos({10, 10}, .FirstUseEver)
		imgui.SetNextWindowSize({220, 100}, .FirstUseEver)
		if imgui.Begin("Graphon", nil, {.NoCollapse}) {
			fps_buf: [32]u8
			fps_str := fmt.bprintf(fps_buf[:], "FPS: %d\x00", rl.GetFPS())
			imgui.Text(cstring(raw_data(fps_buf[:])))

			grid_buf: [64]u8
			fmt.bprintf(grid_buf[:], "Grid: %dx%d  Cell: %.0fpx\x00", grid.cols, grid.rows, grid.cell_w)
			imgui.Text(cstring(raw_data(grid_buf[:])))

			font_buf: [32]u8
			fmt.bprintf(font_buf[:], "Font size: %d\x00", grid.font_size)
			imgui.Text(cstring(raw_data(font_buf[:])))

			fidelity_names := [Fidelity]cstring{
				.FULL_ONLY  = "FULL_ONLY (rect)",
				.DENSITY    = "DENSITY",
				.HALF       = "HALF",
				.FRACTIONAL = "FRACTIONAL",
				.ALL        = "ALL",
			}
			fid_buf: [48]u8
			fmt.bprintf(fid_buf[:], "Fidelity: %s\x00", fidelity_names[grid.fidelity])
			imgui.Text(cstring(raw_data(fid_buf[:])))

			imgui.Separator()
			mode_names := [3]cstring{"Random", "Solver", "Primitives"}
			mode_buf: [32]u8
			fmt.bprintf(mode_buf[:], "Mode: %s\x00", mode_names[demo_mode])
			imgui.Text(cstring(raw_data(mode_buf[:])))

			if demo_mode == 1 {
				blend_names := [BlendMode]cstring{
					.Normal   = "Normal",
					.Alpha    = "Alpha",
					.Additive = "Additive",
					.Multiply = "Multiply",
				}
				bl_buf: [32]u8
				fmt.bprintf(bl_buf[:], "Blend: %s\x00", blend_names[demo_blend])
				imgui.Text(cstring(raw_data(bl_buf[:])))
			}
		}
		imgui.End()

		rlimgui.end()
		rl.EndDrawing()
	}
}

load_font :: proc(size: i32) -> rl.Font {
	codepoints := ALL_CODEPOINTS
	font := rl.LoadFontEx(FONT_PATH, size, raw_data(codepoints[:]), i32(len(codepoints)))
	rl.SetTextureFilter(font.texture, .POINT)
	return font
}

resize_font :: proc(grid: ^Grid, font: ^rl.Font, new_size: i32, demo_mode: int = 0, palette: ^Palette = nil, blend: BlendMode = .Normal, patterns: ^PatternLib = nil) {
	size := clamp(new_size, 4, 64)
	rl.UnloadFont(font^)
	font^ = load_font(size)
	grid_resize(grid, i32(rl.GetScreenWidth()), i32(rl.GetScreenHeight()), font^, size)
	refresh_demo(grid, demo_mode, palette, blend, patterns)
}

refresh_demo :: proc(grid: ^Grid, mode: int, palette: ^Palette, blend: BlendMode, patterns: ^PatternLib) {
	switch mode {
	case 0: randomize_grid(grid)
	case 1: if palette != nil do fill_solver_demo(grid, palette, blend)
	case 2: if palette != nil && patterns != nil do fill_primitives_demo(grid, palette, patterns)
	}
}

randomize_grid :: proc(grid: ^Grid) {
	// Build available character pool based on fidelity
	pool: [32]rune
	pool_len: u32 = 0

	density := DENSITY_CHARS
	half := HALF_CHARS
	fractional := FRACTIONAL_CHARS
	quarter := QUARTER_CHARS

	if grid.fidelity >= .DENSITY {
		for c in density { pool[pool_len] = c; pool_len += 1 }
	}
	if grid.fidelity >= .HALF {
		for c in half { pool[pool_len] = c; pool_len += 1 }
	}
	if grid.fidelity >= .FRACTIONAL {
		for c in fractional { pool[pool_len] = c; pool_len += 1 }
	}
	if grid.fidelity >= .ALL {
		for c in quarter { pool[pool_len] = c; pool_len += 1 }
	}

	// FULL_ONLY — just use full block, character won't be drawn anyway
	if pool_len == 0 {
		pool[0] = '█'
		pool_len = 1
	}

	for i in 0 ..< len(grid.cells) {
		grid.cells[i] = Grafel{
			char = pool[rand.uint32() % pool_len],
			fg   = {u8(rand.uint32() % 256), u8(rand.uint32() % 256), u8(rand.uint32() % 256), 255},
			bg   = {u8(rand.uint32() % 256), u8(rand.uint32() % 256), u8(rand.uint32() % 256), 255},
		}
	}
}

// Primitives demo: shapes, text, and patterns
fill_primitives_demo :: proc(grid: ^Grid, palette: ^Palette, patterns: ^PatternLib) {
	clear_grid(grid, palette_get(palette, "dark"))

	white := palette_get(palette, "white")
	red := palette_get(palette, "red")
	green := palette_get(palette, "green")
	blue := palette_get(palette, "blue")
	cyan := palette_get(palette, "cyan")
	yellow := palette_get(palette, "yellow")
	magenta := palette_get(palette, "magenta")

	// Title
	draw_text(grid, 2, 1, "GRAPHON", white, {0, 0, 0, 0}, 2)

	// Shapes
	fill_rect(grid, 2, 12, 12, 6, blue, 0.75)
	draw_rect(grid, 2, 12, 12, 6, cyan)
	fill_circle(grid, 26, 15, 5, red, 0.5)
	draw_circle(grid, 26, 15, 5, yellow)
	draw_line(grid, 36, 10, 50, 20, green)
	draw_line(grid, 36, 20, 50, 10, magenta)

	// Text samples
	draw_text(grid, 2, 22, "ABCDEFGHIJKLM", white)
	draw_text(grid, 2, 28, "NOPQRSTUVWXYZ", white)
	draw_text(grid, 2, 34, "0123456789", yellow)
	draw_text(grid, 2, 40, "HELLO WORLD!", green)

	// Patterns
	draw_pattern(grid, patterns, 56, 12, "heart")
	draw_pattern(grid, patterns, 56, 18, "star")
	draw_pattern(grid, patterns, 64, 12, "heart", blue)
	draw_pattern(grid, patterns, 64, 18, "star", cyan)

	// Opacity gradient bar
	for col in 0 ..< min(40, grid.cols - 2) {
		opacity := f32(col) / 39.0
		plot_grafel(grid, 2 + col, 47, white, opacity)
	}
}

// Solver demo: horizontal opacity gradient using palette colors, one row per color
fill_solver_demo :: proc(grid: ^Grid, palette: ^Palette, blend: BlendMode) {
	bg := palette_get(palette, "dark")
	colors := [7]string{"red", "green", "blue", "cyan", "magenta", "yellow", "orange"}

	for row in 0 ..< grid.rows {
		color_name := colors[row % len(colors)]
		fg := palette_get(palette, color_name)

		for col in 0 ..< grid.cols {
			opacity := f32(col) / f32(max(grid.cols - 1, 1))
			grid_set(grid, col, row, solve_cell(fg, opacity, bg, blend))
		}
	}
}
