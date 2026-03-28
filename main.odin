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

	// Lighting
	scene_lights := lighting_create({40, 40, 50, 255})
	defer lighting_destroy(&scene_lights)
	add_directional(&scene_lights, {-0.5, -1, -0.3}, {255, 240, 220, 255}, 0.8)
	add_point_light(&scene_lights, {0, 6, 0}, {255, 100, 50, 255}, 1.2, 20.0)

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
			fill_3d_demo(&grid, &db, &cam, &palette, &scene_lights, time)
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

// Plot a 3D point with lighting applied
plot_3d_lit :: proc(grid: ^Grid, db: ^DepthBuffer, cam: ^Camera, lights: ^Lighting, point: rl.Vector3, color: [4]u8, fog_color: [4]u8) {
	lit := light_point_simple(lights, color, point)
	plot_3d(grid, db, cam, point, lit, fog_color)
}

// 3D demo: solid rasterized meshes with lighting
fill_3d_demo :: proc(grid: ^Grid, db: ^DepthBuffer, cam: ^Camera, palette: ^Palette, lights: ^Lighting, time: f32) {
	fog_color := palette_get(palette, "dark")
	clear_grid(grid, fog_color)
	depth_buffer_clear(db)

	green := palette_get(palette, "green")
	blue := palette_get(palette, "blue")
	red := palette_get(palette, "red")
	cyan := palette_get(palette, "cyan")
	yellow := palette_get(palette, "yellow")
	white := palette_get(palette, "white")
	gray := palette_get(palette, "gray")

	// Move the point light in a circle
	lights.lights[1].position = {math.cos(time * 0.7) * 8, 6, math.sin(time * 0.7) * 8}

	// Ground plane — subdivided for smooth lighting
	tile_size: f32 = 4
	for gz: f32 = -20; gz < 20; gz += tile_size {
		for gx: f32 = -20; gx < 20; gx += tile_size {
			raster_quad(grid, db, cam,
				{gx, 0, gz + tile_size},
				{gx + tile_size, 0, gz + tile_size},
				{gx + tile_size, 0, gz},
				{gx, 0, gz},
				gray, lights, fog_color,
			)
		}
	}

	// Spinning cube — solid rasterized box
	raster_box_rotated(grid, db, cam,
		{0, 4, 0}, {4, 4, 4}, red,
		time,
		lights, fog_color,
	)

	// Colored pillars — solid boxes
	pillar_colors := [4][4]u8{green, blue, cyan, yellow}
	pillar_positions := [4][2]f32{{-8, -5}, {8, -5}, {-8, 5}, {8, 5}}
	for i in 0 ..< 4 {
		px := pillar_positions[i][0]
		pz := pillar_positions[i][1]
		raster_box(grid, db, cam,
			{px, 3, pz}, {1.5, 6, 1.5}, pillar_colors[i],
			lights, fog_color,
		)
	}

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
