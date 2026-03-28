package main

import rl "vendor:raylib"
import "core:math"
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

	demo_mode: int = 0 // 0=random, 1=solver, 2=primitives, 3=3D
	demo_blend := BlendMode.Normal

	// 3D state
	cam := camera_create({0, 5, 12}, {0, 0, 0})
	db := depth_buffer_create(grid.cols, grid.rows)
	defer depth_buffer_destroy(&db)
	time: f32 = 0

	mouse: Mouse
	show_cursor := true
	paint_color := palette_get(&palette, "white")

	randomize_grid(&grid)

	for !rl.WindowShouldClose() {
		// Update mouse
		mouse_update(&mouse, &grid)
		// Font size adjustment
		do_resize :: proc(grid: ^Grid, font: ^rl.Font, new_size: i32, demo_mode: int, palette: ^Palette, blend: BlendMode, patterns: ^PatternLib, db: ^DepthBuffer) {
			resize_font(grid, font, new_size, demo_mode, palette, blend, patterns)
			depth_buffer_resize(db, grid.cols, grid.rows)
		}
		if rl.IsKeyPressed(.UP) {
			do_resize(&grid, &font, grid.font_size + 2, demo_mode, &palette, demo_blend, &patterns, &db)
		}
		if rl.IsKeyPressed(.DOWN) {
			do_resize(&grid, &font, grid.font_size - 2, demo_mode, &palette, demo_blend, &patterns, &db)
		}
		if rl.IsKeyPressed(.LEFT) {
			do_resize(&grid, &font, grid.font_size - 1, demo_mode, &palette, demo_blend, &patterns, &db)
		}
		if rl.IsKeyPressed(.RIGHT) {
			do_resize(&grid, &font, grid.font_size + 1, demo_mode, &palette, demo_blend, &patterns, &db)
		}

		// Cycle demo mode: 0=random, 1=solver, 2=primitives, 3=3D
		if rl.IsKeyPressed(.TAB) {
			demo_mode = (demo_mode + 1) % 4
			if demo_mode != 3 {
				refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
			}
		}

		// 3D mode: update camera and re-render every frame
		if demo_mode == 3 {
			dt := rl.GetFrameTime()
			time += dt
			camera_update(&cam, dt)
			fill_3d_demo(&grid, &db, &cam, &palette, time)
		}

		// Cycle blend mode in solver demo
		if demo_mode == 1 && rl.IsKeyPressed(.B) {
			demo_blend = BlendMode((int(demo_blend) + 1) % 4)
			refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
		}

		// Toggle cursor
		if rl.IsKeyPressed(.C) {
			show_cursor = !show_cursor
		}

		// Paint with mouse (left = paint, right = erase)
		io := imgui.GetIO()
		imgui_wants_mouse := io.WantCaptureMouse
		if mouse.in_bounds && !imgui_wants_mouse {
			if mouse.left {
				plot_grafel(&grid, mouse.col, mouse.row, paint_color, 1.0)
			}
			if mouse.right {
				bg := [4]u8{32, 32, 32, 255}
				grid_set(&grid, mouse.col, mouse.row, Grafel{char = '█', fg = bg, bg = bg})
			}
		}

		// Re-randomize / refresh on SPACE
		if rl.IsKeyPressed(.SPACE) {
			refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Render Grafel grid with cursor overlay
		saved_cell: Grafel
		cursor_active := show_cursor && mouse.in_bounds
		if cursor_active {
			saved_cell = grid_get(&grid, mouse.col, mouse.row)
			draw_cursor(&grid, &mouse)
		}
		render_grid(&grid, font)
		if cursor_active {
			grid_set(&grid, mouse.col, mouse.row, saved_cell)
		}

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
			mode_names := [4]cstring{"Random", "Solver", "Primitives", "3D"}
			mode_buf: [32]u8
			fmt.bprintf(mode_buf[:], "Mode: %s\x00", mode_names[demo_mode])
			imgui.Text(cstring(raw_data(mode_buf[:])))

			mouse_buf: [48]u8
			fmt.bprintf(mouse_buf[:], "Mouse: %d, %d\x00", mouse.col, mouse.row)
			imgui.Text(cstring(raw_data(mouse_buf[:])))

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
	case 3: // 3D mode refreshes per-frame in main loop
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

// 3D demo: spinning cube + ground plane + pillars
fill_3d_demo :: proc(grid: ^Grid, db: ^DepthBuffer, cam: ^Camera, palette: ^Palette, time: f32) {
	clear_grid(grid, palette_get(palette, "dark"))
	depth_buffer_clear(db)

	fog_color := palette_get(palette, "dark")
	green := palette_get(palette, "green")
	blue := palette_get(palette, "blue")
	red := palette_get(palette, "red")
	cyan := palette_get(palette, "cyan")
	yellow := palette_get(palette, "yellow")
	white := palette_get(palette, "white")
	gray := palette_get(palette, "gray")

	// Ground plane (grid of points)
	for gz: f32 = -20; gz <= 20; gz += 1 {
		for gx: f32 = -20; gx <= 20; gx += 1 {
			checker := (int(gx + 100) + int(gz + 100)) % 2 == 0
			color := checker ? gray : palette_get(palette, "dark")
			if color[0] == fog_color[0] && color[1] == fog_color[1] && color[2] == fog_color[2] do continue
			plot_3d(grid, db, cam, {gx, 0, gz}, color, fog_color)
		}
	}

	// Spinning cube
	cube_size: f32 = 2.0
	cos_t := math.cos(time)
	sin_t := math.sin(time)

	for z: f32 = -cube_size; z <= cube_size; z += 0.3 {
		for y: f32 = -cube_size; y <= cube_size; y += 0.3 {
			for x: f32 = -cube_size; x <= cube_size; x += 0.3 {
				// Only draw surface
				is_surface := abs(x) > cube_size - 0.4 || abs(y) > cube_size - 0.4 || abs(z) > cube_size - 0.4
				if !is_surface do continue

				// Rotate around Y axis
				rx := x * cos_t - z * sin_t
				rz := x * sin_t + z * cos_t

				plot_3d(grid, db, cam, {rx, y + 4, rz}, red, fog_color)
			}
		}
	}

	// Colored pillars
	pillar_colors := [4][4]u8{green, blue, cyan, yellow}
	pillar_positions := [4][2]f32{{-8, -5}, {8, -5}, {-8, 5}, {8, 5}}
	for i in 0 ..< 4 {
		px := pillar_positions[i][0]
		pz := pillar_positions[i][1]
		for py: f32 = 0; py <= 6; py += 0.3 {
			plot_3d(grid, db, cam, {px, py, pz}, pillar_colors[i], fog_color)
		}
	}

	// Floating text label
	draw_text(grid, 2, 1, "3D MODE - WASD+MOUSE", white)
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
