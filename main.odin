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
INIT_FONT_SZ :: i32(1)
FONT_PATH    :: "assets/JetBrainsMonoNLNerdFont-Regular.ttf"

// Demo draw callback — draws primitives that live in the demo, NOT the renderer
demo_draw :: proc(s3d: ^Scene3D, use_shader: bool) {
	// Ground plane — only in color pass (receives shadows, doesn't cast them)
	if use_shader {
		rl.DrawPlane({0, 0, 0}, {40, 40}, {120, 115, 105, 255})
	}

	// Cube
	rl.DrawCubeV({0, 2, 0}, {3, 3, 3}, {220, 50, 40, 255})

	// Pillars
	pillar_colors := [4]rl.Color{{50, 200, 80, 255}, {80, 100, 220, 255}, {200, 80, 180, 255}, {80, 200, 200, 255}}
	pillar_pos := [4]rl.Vector3{{-8, 3, -5}, {8, 3, -5}, {-8, 3, 5}, {8, 3, 5}}
	for i in 0 ..< 4 {
		rl.DrawCylinder(pillar_pos[i], 0.6, 0.6, 6, 32, pillar_colors[i])
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Graphon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(0)

	// ImGui
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	rlimgui.init()
	defer rlimgui.shutdown()

	// --- Graphon renderer ---
	g := graphon_init(SCREEN_W, SCREEN_H, FONT_PATH, INIT_FONT_SZ)
	defer graphon_destroy(&g)

	// --- 3D Scene ---
	scene := scene_create()
	scene.camera = camera_create({-8, 6, 14}, {0, 1, 0})

	// Lights
	scene_add_light(&scene, .Directional, {10, 15, 5}, {-1, 0, -0.5}, {0.9, 0.75, 0.5})
	orbit_light_idx := scene_add_light(&scene, .Point, {8, 3, 0}, {0, 0, 0}, {1.2, 0.8, 0.3})
	scene_add_light(&scene, .Point, {-6, 4, -6}, {0, 0, 0}, {0.2, 0.3, 0.8})
	scene_add_light(&scene, .Point, {8, 3, 8}, {0, 0, 0}, {0.15, 0.6, 0.2})

	// Volumes
	scene_add_volume(&scene, {-20, -1, -20}, {-5, 10, 20}, {0.05, 0.08, 0.2}, 0.3)

	// Model
	suzanne := rl.LoadModel("assets/suzanne.obj")
	defer rl.UnloadModel(suzanne)
	scene_add_model(&scene, suzanne, {-5, 2, 0}, material_create({255, 165, 50, 255}), 2.0)
	// Make Suzanne auto-rotate
	scene.objects[scene.object_count - 1].auto_rotate = true
	scene.objects[scene.object_count - 1].rotate_speed = 0.5

	// --- 2D state (demos) ---
	palette := palette_create()
	defer palette_destroy(&palette)
	palette_default(&palette)

	patterns := pattern_lib_create()
	defer pattern_lib_destroy(&patterns)
	pattern_define(&patterns, "heart", {".#.#.", "#####", "#####", ".###.", "..#.."}, palette_get(&palette, "red"))
	pattern_define(&patterns, "star", {"..#..", ".###.", "#####", ".###.", "..#.."}, palette_get(&palette, "yellow"))

	ls := layer_stack_create(g.grid.cols, g.grid.rows)
	defer layer_stack_destroy(&ls)

	cp := compute_create(g.grid.cols, g.grid.rows)
	defer compute_destroy(&cp)


	demo_mode: int = 0
	demo_blend := BlendMode.Normal
	canvas_mode := false
	time: f32 = 0

	mouse: Mouse
	show_cursor := true
	paint_color := palette_get(&palette, "white")

	randomize_grid(&g.grid)

	for !rl.WindowShouldClose() {
		mouse_update(&mouse, &g.grid)
		dt := rl.GetFrameTime()
		time += dt

		// Font size
		if rl.IsKeyPressed(.UP)    { graphon_resize_font(&g, g.font_size + 2); layer_stack_resize(&ls, g.grid.cols, g.grid.rows); compute_resize(&cp, g.grid.cols, g.grid.rows); refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns) }
		if rl.IsKeyPressed(.DOWN)  { graphon_resize_font(&g, g.font_size - 2); layer_stack_resize(&ls, g.grid.cols, g.grid.rows); compute_resize(&cp, g.grid.cols, g.grid.rows); refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns) }
		if rl.IsKeyPressed(.LEFT)  { graphon_resize_font(&g, g.font_size - 1); layer_stack_resize(&ls, g.grid.cols, g.grid.rows); compute_resize(&cp, g.grid.cols, g.grid.rows); refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns) }
		if rl.IsKeyPressed(.RIGHT) { graphon_resize_font(&g, g.font_size + 1); layer_stack_resize(&ls, g.grid.cols, g.grid.rows); compute_resize(&cp, g.grid.cols, g.grid.rows); refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns) }

		// Mode cycling
		if rl.IsKeyPressed(.TAB) {
			demo_mode = (demo_mode + 1) % 7
			if demo_mode != 3 && demo_mode != 4 && demo_mode != 5 && demo_mode != 6 {
				refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns)
			}
		}

		// Scene updates
		if !canvas_mode {
			if demo_mode == 3 {
				camera_update(&scene.camera, dt)

				// Orbit warm light
				if orbit_light_idx >= 0 {
					scene.lights[orbit_light_idx].position = {
						math.cos(time * 0.5) * 6,
						2.5,
						math.sin(time * 0.5) * 6,
					}
				}

				// Sync lights to renderer
				g.scene3d.light_count = 0
				for i in 0 ..< scene.light_count {
					l := &scene.lights[i]
					scene3d_add_light(&g.scene3d, l.type, l.position, l.target, l.color)
				}

				// Render 3D
				scene3d_render(&g.scene3d, &scene.camera, scene.objects[:scene.object_count], time, demo_draw)
			}

			is_compute_mode := demo_mode >= 5
			if is_compute_mode && cp.enabled && demo_mode != 3 {
				compute_run(&cp, demo_mode, time, &g.grid, int(demo_blend), &scene.camera)
			}
			if !is_compute_mode && demo_mode != 3 {
				if demo_mode == 4 {
					fill_layers_demo(&g.grid, &ls, &palette, time)
				}
			}
			if demo_mode == 1 && rl.IsKeyPressed(.B) {
				demo_blend = BlendMode((int(demo_blend) + 1) % 4)
				refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns)
			}
		}

		// Input
		if rl.IsKeyPressed(.C) { show_cursor = !show_cursor }
		io := imgui.GetIO()
		if mouse.in_bounds && !io.WantCaptureMouse {
			if mouse.left { plot_grafel(&g.grid, mouse.col, mouse.row, paint_color, 1.0) }
			if mouse.right {
				bg := [4]u8{32, 32, 32, 255}
				grid_set(&g.grid, mouse.col, mouse.row, Grafel{char = '█', fg = bg, bg = bg})
			}
		}
		if rl.IsKeyPressed(.SPACE) { refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns) }

		// Debug toggles
		if rl.IsKeyPressed(.F1) { g.config.show_grid_lines = !g.config.show_grid_lines }
		if rl.IsKeyPressed(.F2) { g.config.show_cell_coords = !g.config.show_cell_coords }
		if rl.IsKeyPressed(.F4) { graphon_cycle_fx(&g) }
		if rl.IsKeyPressed(.F7) {
			g.grid.forced_fidelity = !g.grid.forced_fidelity
			if !g.grid.forced_fidelity { g.grid.fidelity = .ALL }
		}
		if rl.IsKeyPressed(.F8) && g.grid.forced_fidelity {
			g.grid.fidelity = Fidelity((int(g.grid.fidelity) + 1) % 5)
		}
		if rl.IsKeyPressed(.F9) {
			canvas_mode = !canvas_mode
			if canvas_mode { clear_grid(&g.grid, palette_get(&palette, "dark")) }
			else { refresh_demo(&g.grid, demo_mode, &palette, demo_blend, &patterns) }
		}
		if rl.IsKeyPressed(.F11) { rl.ToggleBorderlessWindowed() }
		if rl.IsKeyPressed(.F12) { export_screenshot() }
		if rl.IsKeyPressed(.F5) { save_scene(&g.grid, "scene.grf") }

		// Cursor overlay
		saved_cell: Grafel
		cursor_active := show_cursor && mouse.in_bounds
		if cursor_active {
			saved_cell = grid_get(&g.grid, mouse.col, mouse.row)
			draw_cursor(&g.grid, &mouse)
		}

		// --- Render ---
		use_postfx := g.gpu.active_fx != .None

		if use_postfx { gpu_begin(&g.gpu) }
		else { rl.BeginDrawing(); rl.ClearBackground(rl.BLACK) }

		is_gpu_only_mode := demo_mode >= 5
		has_gpu_tex := false
		gpu_tex: rl.Texture2D
		gpu_cols, gpu_rows: int

		if demo_mode == 3 && g.scene3d.enabled {
			has_gpu_tex = true
			gpu_tex = scene3d_get_output(&g.scene3d)
			gpu_cols = g.grid.cols
			gpu_rows = g.grid.rows
		} else if is_gpu_only_mode && cp.enabled && cp.target.texture.id != 0 {
			has_gpu_tex = true
			gpu_tex = cp.target.texture
			gpu_cols = cp.cols
			gpu_rows = cp.rows
		}

		if has_gpu_tex {
			gpu_grid_render(&g.gpu_grid, &g.grid, g.font, true, gpu_tex, gpu_cols, gpu_rows)
		} else {
			gpu_grid_upload(&g.gpu_grid, &g.grid)
			gpu_grid_render(&g.gpu_grid, &g.grid, g.font)
		}

		// Debug overlays
		overlay_cols := gpu_cols > 0 ? gpu_cols : g.grid.cols
		overlay_rows := gpu_rows > 0 ? gpu_rows : g.grid.rows
		if g.config.show_grid_lines { debug_grid_lines(&g.grid, overlay_cols, overlay_rows) }
		if g.config.show_cell_coords { debug_cell_coords(&g.grid, g.font, overlay_cols, overlay_rows) }

		if use_postfx {
			gpu_end(&g.gpu)
			rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK)
			gpu_present(&g.gpu, time)
		}

		if cursor_active { grid_set(&g.grid, mouse.col, mouse.row, saved_cell) }

		// ImGui
		rlimgui.begin()
		imgui.SetNextWindowPos({10, 10}, .FirstUseEver)
		imgui.SetNextWindowSize({220, 100}, .FirstUseEver)
		if imgui.Begin("Graphon", nil, {.NoCollapse}) {
			fps_buf: [32]u8
			fmt.bprintf(fps_buf[:], "FPS: %d\x00", rl.GetFPS())
			imgui.Text(cstring(raw_data(fps_buf[:])))

			grid_buf: [64]u8
			fmt.bprintf(grid_buf[:], "Grid: %dx%d  Cell: %.0fpx\x00", g.grid.cols, g.grid.rows, g.grid.cell_w)
			imgui.Text(cstring(raw_data(grid_buf[:])))

			font_buf: [32]u8
			fmt.bprintf(font_buf[:], "Font size: %d\x00", g.grid.font_size)
			imgui.Text(cstring(raw_data(font_buf[:])))

			imgui.Separator()
			mode_names := [7]cstring{"Random", "Solver", "Primitives", "3D", "Layers", "Compute", "Showcase"}
			mode_buf: [32]u8
			fmt.bprintf(mode_buf[:], "Mode: %s (%s)\x00", mode_names[demo_mode], canvas_mode ? "CANVAS" : "DEMO")
			imgui.Text(cstring(raw_data(mode_buf[:])))

			imgui.Separator()
			fx_names := [PostFX]cstring{.None = "None", .Bloom = "Bloom", .Scanlines = "Scanlines", .Chromatic = "Chromatic"}
			fx_buf: [32]u8
			fmt.bprintf(fx_buf[:], "PostFX: %s\x00", fx_names[g.gpu.active_fx])
			imgui.Text(cstring(raw_data(fx_buf[:])))

			fid_names := [Fidelity]cstring{.FULL_ONLY = "FULL_ONLY", .DENSITY = "DENSITY", .HALF = "HALF", .FRACTIONAL = "FRACTIONAL", .ALL = "ALL"}
			fid_buf: [48]u8
			fmt.bprintf(fid_buf[:], "Fidelity: %s (%s)\x00", fid_names[g.grid.fidelity], g.grid.forced_fidelity ? "forced" : "auto")
			imgui.Text(cstring(raw_data(fid_buf[:])))

			imgui.Separator()
			imgui.Text("TAB:Mode  WASD:Camera  F4:PostFX")
			imgui.Text("F7:Fidelity F9:Canvas F12:Screenshot")
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
	size := clamp(new_size, 1, 64)
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
	case 3: // 3D renders per-frame
	case 4: // Layers renders per-frame
	case 5: // Compute
	case 6: // Showcase
	}
}

randomize_grid :: proc(grid: ^Grid) {
	pool: [32]rune
	pool_len: u32 = 0
	density := DENSITY_CHARS
	half := HALF_CHARS
	fractional := FRACTIONAL_CHARS
	quarter := QUARTER_CHARS
	if grid.fidelity >= .DENSITY    { for c in density     { pool[pool_len] = c; pool_len += 1 } }
	if grid.fidelity >= .HALF       { for c in half        { pool[pool_len] = c; pool_len += 1 } }
	if grid.fidelity >= .FRACTIONAL { for c in fractional  { pool[pool_len] = c; pool_len += 1 } }
	if grid.fidelity >= .ALL        { for c in quarter     { pool[pool_len] = c; pool_len += 1 } }
	if pool_len == 0 { pool[0] = '█'; pool_len = 1 }
	for i in 0 ..< len(grid.cells) {
		grid.cells[i] = Grafel{
			char = pool[rand.uint32() % pool_len],
			fg   = {u8(rand.uint32() % 256), u8(rand.uint32() % 256), u8(rand.uint32() % 256), 255},
			bg   = {u8(rand.uint32() % 256), u8(rand.uint32() % 256), u8(rand.uint32() % 256), 255},
		}
	}
}

fill_primitives_demo :: proc(grid: ^Grid, palette: ^Palette, patterns: ^PatternLib) {
	clear_grid(grid, palette_get(palette, "dark"))
	white := palette_get(palette, "white")
	red := palette_get(palette, "red")
	green := palette_get(palette, "green")
	blue := palette_get(palette, "blue")
	cyan := palette_get(palette, "cyan")
	yellow := palette_get(palette, "yellow")
	magenta := palette_get(palette, "magenta")
	draw_text(grid, 2, 1, "GRAPHON", white, {0, 0, 0, 0}, 2)
	fill_rect(grid, 2, 12, 12, 6, blue, 0.75)
	draw_rect(grid, 2, 12, 12, 6, cyan)
	fill_circle(grid, 26, 15, 5, red, 0.5)
	draw_circle(grid, 26, 15, 5, yellow)
	draw_line(grid, 36, 10, 50, 20, green)
	draw_line(grid, 36, 20, 50, 10, magenta)
	draw_text(grid, 2, 22, "ABCDEFGHIJKLM", white)
	draw_text(grid, 2, 28, "NOPQRSTUVWXYZ", white)
	draw_text(grid, 2, 34, "0123456789", yellow)
	draw_text(grid, 2, 40, "HELLO WORLD!", green)
	draw_pattern(grid, patterns, 56, 12, "heart")
	draw_pattern(grid, patterns, 56, 18, "star")
	draw_pattern(grid, patterns, 64, 12, "heart", blue)
	draw_pattern(grid, patterns, 64, 18, "star", cyan)
	for col in 0 ..< min(40, grid.cols - 2) {
		opacity := f32(col) / 39.0
		plot_grafel(grid, 2 + col, 47, white, opacity)
	}
}

fill_layers_demo :: proc(grid: ^Grid, ls: ^LayerStack, palette: ^Palette, time: f32) {
	layer_clear_all(ls)
	white := palette_get(palette, "white")
	red := palette_get(palette, "red")
	green := palette_get(palette, "green")
	blue := palette_get(palette, "blue")
	cyan := palette_get(palette, "cyan")
	yellow := palette_get(palette, "yellow")
	for row in 0 ..< ls.rows {
		for col in 0 ..< ls.cols {
			brightness := u8(20 + int(f32(row) / f32(ls.rows) * 30))
			layer_set(ls, .Background, col, row, Grafel{char = '█', fg = {brightness, brightness, brightness + 10, 255}, bg = {brightness, brightness, brightness + 10, 255}})
		}
	}
	for col in 5 ..< min(45, ls.cols) { for row in 20 ..< min(35, ls.rows) { layer_plot(ls, .World, col, row, blue, 0.75) } }
	for col in 30 ..< min(60, ls.cols) { for row in 15 ..< min(30, ls.rows) { layer_plot(ls, .World, col, row, green, 0.5) } }
	cx := int(f32(ls.cols) / 2 + math.cos(time) * 15)
	cy := int(f32(ls.rows) / 2 + math.sin(time * 0.7) * 8)
	for row in cy - 4 ..= cy + 4 { for col in cx - 4 ..= cx + 4 { if (col-cx)*(col-cx)+(row-cy)*(row-cy) <= 16 { layer_plot(ls, .Entity, col, row, red, 1.0) } } }
	glow_r := 6 + int(math.sin(time * 3) * 2)
	for row in cy - glow_r ..= cy + glow_r { for col in cx - glow_r ..= cx + glow_r { dist_sq := (col-cx)*(col-cx)+(row-cy)*(row-cy); if dist_sq <= glow_r*glow_r && dist_sq > 16 { layer_plot(ls, .Effects, col, row, yellow, (1.0 - f32(dist_sq)/f32(glow_r*glow_r))*0.6, .Additive) } } }
	ui_grid := Grid{cells = ls.layers[LayerID.UI], cols = ls.cols, rows = ls.rows, cell_w = grid.cell_w, cell_h = grid.cell_h, font_size = grid.font_size, fidelity = grid.fidelity}
	draw_text(&ui_grid, 2, 1, "LAYERS DEMO", white)
	draw_text(&ui_grid, 2, 7, "BG  WORLD  ENTITY  FX  UI", cyan)
	layer_composite(ls)
	layer_to_grid(ls, grid)
}

fill_solver_demo :: proc(grid: ^Grid, palette: ^Palette, blend: BlendMode) {
	bg := palette_get(palette, "dark")
	colors := [7]string{"red", "green", "blue", "cyan", "magenta", "yellow", "orange"}
	for row in 0 ..< grid.rows {
		fg := palette_get(palette, colors[row % len(colors)])
		for col in 0 ..< grid.cols {
			grid_set(grid, col, row, solve_cell(fg, f32(col) / f32(max(grid.cols - 1, 1)), bg, blend))
		}
	}
}
