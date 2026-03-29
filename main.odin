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

// Render path
RenderPath :: enum {
	CPU,     // CPU fills buffer + CPU draws each cell
	Hybrid,  // CPU fills buffer + GPU displays (one draw call)
	GPU,     // GPU compute fills + GPU displays (zero CPU)
}

RENDER_PATH_COUNT :: 3

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Graphon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(0) // uncapped — see true performance

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

	demo_mode: int = 0 // 0=random, 1=solver, 2=primitives, 3=3D, 4=layers
	demo_blend := BlendMode.Normal

	// Layer stack
	ls := layer_stack_create(grid.cols, grid.rows)
	defer layer_stack_destroy(&ls)

	// Compute pipeline (GPU-generated scenes)
	cp := compute_create(grid.cols, grid.rows)
	defer compute_destroy(&cp)

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

	cfg := config_default()

	// Model loading
	suzanne := rl.LoadModel("assets/suzanne.obj")
	defer rl.UnloadModel(suzanne)

	// GPU 3D scene renderer (Raylib native 3D → Grafel glyph shader)
	scene3d := scene3d_create(grid.cols, grid.rows)
	defer scene3d_destroy(&scene3d)

	// GPU pipeline (post-process)
	gpu := gpu_create(SCREEN_W, SCREEN_H)
	defer gpu_destroy(&gpu)

	// GPU grid renderer (hybrid + GPU display)
	gg := gpu_grid_create(grid.cols, grid.rows)
	defer gpu_grid_destroy(&gg)
	render_path := RenderPath.CPU

	mouse: Mouse
	show_cursor := true
	paint_color := palette_get(&palette, "white")
	canvas_mode := false // false = Demo, true = Canvas

	randomize_grid(&grid)

	for !rl.WindowShouldClose() {
		// Update mouse
		mouse_update(&mouse, &grid)
		// Font size adjustment
		do_resize :: proc(grid: ^Grid, font: ^rl.Font, new_size: i32, demo_mode: int, palette: ^Palette, blend: BlendMode, patterns: ^PatternLib, db: ^DepthBuffer, ls: ^LayerStack, gg_ptr: ^GPUGrid, cp_ptr: ^ComputePipeline, render_path: RenderPath, s3d: ^Scene3D = nil) {
			resize_font(grid, font, new_size, demo_mode, palette, blend, patterns)
			// Only resize heavy CPU buffers when not in GPU-only mode
			if render_path != .GPU || grid.cols * grid.rows < 500000 {
				depth_buffer_resize(db, grid.cols, grid.rows)
				layer_stack_resize(ls, grid.cols, grid.rows)
			}
			gpu_grid_resize(gg_ptr, grid.cols, grid.rows)
			compute_resize(cp_ptr, grid.cols, grid.rows)
			if s3d != nil { scene3d_resize(s3d, grid.cols, grid.rows) }
		}
		if rl.IsKeyPressed(.UP) {
			do_resize(&grid, &font, grid.font_size + 2, demo_mode, &palette, demo_blend, &patterns, &db, &ls, &gg, &cp, render_path, &scene3d)
		}
		if rl.IsKeyPressed(.DOWN) {
			do_resize(&grid, &font, grid.font_size - 2, demo_mode, &palette, demo_blend, &patterns, &db, &ls, &gg, &cp, render_path, &scene3d)
		}
		if rl.IsKeyPressed(.LEFT) {
			do_resize(&grid, &font, grid.font_size - 1, demo_mode, &palette, demo_blend, &patterns, &db, &ls, &gg, &cp, render_path, &scene3d)
		}
		if rl.IsKeyPressed(.RIGHT) {
			do_resize(&grid, &font, grid.font_size + 1, demo_mode, &palette, demo_blend, &patterns, &db, &ls, &gg, &cp, render_path, &scene3d)
		}

		// Cycle demo mode: 0=random, 1=solver, 2=primitives, 3=3D, 4=layers, 5=compute
		if rl.IsKeyPressed(.TAB) {
			demo_mode = (demo_mode + 1) % 7
			if demo_mode != 3 && demo_mode != 4 && demo_mode != 5 && demo_mode != 6 {
				refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
			}
		}

		// Global time — always advances
		dt := rl.GetFrameTime()
		time += dt

		// Demo mode scene updates (skipped in canvas mode)
		if !canvas_mode {
			if demo_mode == 3 {
				camera_update(&cam, dt)
			}
			is_compute_mode := demo_mode >= 5
			// Compute shaders for GPU-only modes
			if (render_path == .GPU || is_compute_mode) && cp.enabled && demo_mode != 3 {
				compute_run(&cp, demo_mode, time, &grid, int(demo_blend), &cam)
			}
			// 3D mode: Raylib native GPU renderer → identical across all display paths
			if demo_mode == 3 {
				scene_objects := [1]Scene3DObject{
					{model = suzanne, loaded = suzanne.meshCount > 0, position = {-5, 2, 0}, scale = 2.0, auto_rotate = true, rotate_speed = 0.5, tint = {255, 165, 50, 255}},
				}
				scene3d_render(&scene3d, &cam, scene_objects[:], time)
			}
			if render_path != .GPU && !is_compute_mode && demo_mode != 3 {
				if demo_mode == 4 {
					fill_layers_demo(&grid, &ls, &palette, time)
				}
			}

			if demo_mode == 1 && rl.IsKeyPressed(.B) {
				demo_blend = BlendMode((int(demo_blend) + 1) % 4)
				refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
			}
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

		// Debug toggles
		if rl.IsKeyPressed(.F1) { cfg.show_grid_lines = !cfg.show_grid_lines }
		if rl.IsKeyPressed(.F2) { cfg.show_cell_coords = !cfg.show_cell_coords }
		if rl.IsKeyPressed(.F3) && demo_mode == 3 { cfg.show_depth = !cfg.show_depth }
		if rl.IsKeyPressed(.F4) { gpu_cycle_fx(&gpu) }
		if rl.IsKeyPressed(.F7) {
			grid.forced_fidelity = !grid.forced_fidelity
			if !grid.forced_fidelity {
				grid.fidelity = fidelity_from_cell_size(grid.cell_w)
			}
		}
		if rl.IsKeyPressed(.F8) && grid.forced_fidelity {
			grid.fidelity = Fidelity((int(grid.fidelity) + 1) % 5)
		}
		if rl.IsKeyPressed(.F6) { render_path = RenderPath((int(render_path) + 1) % RENDER_PATH_COUNT) }
		if rl.IsKeyPressed(.F9) {
			canvas_mode = !canvas_mode
			if canvas_mode {
				clear_grid(&grid, palette_get(&palette, "dark"))
			} else {
				refresh_demo(&grid, demo_mode, &palette, demo_blend, &patterns)
			}
		}
		if rl.IsKeyPressed(.F11) { rl.ToggleBorderlessWindowed() }
		if rl.IsKeyPressed(.F12) { export_screenshot() }

		// Save current scene
		if rl.IsKeyPressed(.F5) { save_scene(&grid, "scene.grf") }

		// Debug: depth buffer visualization (replaces grid content)
		if cfg.show_depth && demo_mode == 3 {
			debug_depth_buffer(&grid, &db)
		}

		// Render Grafel grid with cursor overlay to GPU render texture
		saved_cell: Grafel
		cursor_active := show_cursor && mouse.in_bounds
		if cursor_active {
			saved_cell = grid_get(&grid, mouse.col, mouse.row)
			draw_cursor(&grid, &mouse)
		}

		use_postfx := gpu.active_fx != .None

		if use_postfx {
			gpu_begin(&gpu)
		} else {
			rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK)
		}

		// Determine GPU texture source
		is_gpu_only_mode := demo_mode >= 5
		has_gpu_tex := false
		gpu_tex: rl.Texture2D
		gpu_cols, gpu_rows: int

		if demo_mode == 3 && scene3d.enabled {
			// 3D mode: Raylib rendered scene
			has_gpu_tex = true
			gpu_tex = scene3d.target.texture
			gpu_cols = scene3d.cols
			gpu_rows = scene3d.rows
		} else if is_gpu_only_mode && cp.enabled && cp.target.texture.id != 0 {
			// Compute modes
			has_gpu_tex = true
			gpu_tex = cp.target.texture
			gpu_cols = cp.cols
			gpu_rows = cp.rows
		}

		switch render_path {
		case .CPU:
			if has_gpu_tex {
				gpu_grid_render(&gg, &grid, font, true, gpu_tex, gpu_cols, gpu_rows)
			} else {
				render_grid(&grid, font)
			}
		case .Hybrid:
			if has_gpu_tex {
				gpu_grid_render(&gg, &grid, font, true, gpu_tex, gpu_cols, gpu_rows)
			} else {
				gpu_grid_upload(&gg, &grid)
				gpu_grid_render(&gg, &grid, font)
			}
		case .GPU:
			if has_gpu_tex {
				gpu_grid_render(&gg, &grid, font, true, gpu_tex, gpu_cols, gpu_rows)
			} else {
				gpu_grid_upload(&gg, &grid)
				gpu_grid_render(&gg, &grid, font)
			}
		}
		// GPU mode always uses ALL fidelity — shader handles character selection
		if render_path == .GPU && !grid.forced_fidelity {
			grid.fidelity = .ALL
		}

		// Debug overlays — use compute resolution in GPU mode
		overlay_cols: int
		overlay_rows: int
		if demo_mode == 3 && scene3d.enabled {
			overlay_cols = scene3d.cols
			overlay_rows = scene3d.rows
		} else if has_gpu_tex {
			overlay_cols = gpu_cols
			overlay_rows = gpu_rows
		}
		if cfg.show_grid_lines { debug_grid_lines(&grid, overlay_cols, overlay_rows) }
		if cfg.show_cell_coords { debug_cell_coords(&grid, font, overlay_cols, overlay_rows) }

		if use_postfx {
			gpu_end(&gpu)
			rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK)
			gpu_present(&gpu, time)
		}

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
			app_mode: cstring = canvas_mode ? "CANVAS" : "DEMO"
			am_buf: [32]u8
			fmt.bprintf(am_buf[:], "App: %s (F9)\x00", app_mode)
			imgui.Text(cstring(raw_data(am_buf[:])))

			mode_names := [7]cstring{"Random", "Solver", "Primitives", "3D", "Layers", "Compute", "Showcase"}
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

			imgui.Separator()
			fx_names := [PostFX]cstring{
				.None      = "None",
				.Bloom     = "Bloom",
				.Scanlines = "Scanlines",
				.Chromatic = "Chromatic",
			}
			fx_buf: [32]u8
			fmt.bprintf(fx_buf[:], "PostFX: %s\x00", fx_names[gpu.active_fx])
			imgui.Text(cstring(raw_data(fx_buf[:])))

			path_names := [RenderPath]cstring{
				.CPU    = "CPU",
				.Hybrid = "Hybrid (CPU+GPU)",
				.GPU    = "GPU",
			}
			renderer_str := path_names[render_path]
			ren_buf: [32]u8
			fmt.bprintf(ren_buf[:], "Renderer: %s\x00", renderer_str)
			imgui.Text(cstring(raw_data(ren_buf[:])))

			imgui.Separator()
			fidelity_level_names := [Fidelity]cstring{
				.FULL_ONLY  = "FULL_ONLY",
				.DENSITY    = "DENSITY",
				.HALF       = "HALF",
				.FRACTIONAL = "FRACTIONAL",
				.ALL        = "ALL",
			}
			fid_mode: cstring = grid.forced_fidelity ? "FORCED" : "auto"
			ff_buf: [64]u8
			fmt.bprintf(ff_buf[:], "Fidelity: %s (%s)\x00", fidelity_level_names[grid.fidelity], fid_mode)
			imgui.Text(cstring(raw_data(ff_buf[:])))

			imgui.Text("F1:Grid F2:Coords F3:Depth")
			imgui.Text("F4:PostFX F5:Save F6:Renderer")
			imgui.Text("F7:ForceFidelity F8:CycleFidelity")
			imgui.Text("F12:Screenshot")
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
	case 3: // 3D mode refreshes per-frame in main loop
	case 4: // Layers mode refreshes per-frame in main loop
	case 5: // Compute mode runs on GPU
	case 6: // Showcase mode runs on GPU
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
// Layers demo: 5 layers composited together
fill_layers_demo :: proc(grid: ^Grid, ls: ^LayerStack, palette: ^Palette, time: f32) {
	layer_clear_all(ls)

	white := palette_get(palette, "white")
	red := palette_get(palette, "red")
	green := palette_get(palette, "green")
	blue := palette_get(palette, "blue")
	cyan := palette_get(palette, "cyan")
	yellow := palette_get(palette, "yellow")
	dark := palette_get(palette, "dark")

	// Layer 0: Background — dark with subtle gradient
	for row in 0 ..< ls.rows {
		for col in 0 ..< ls.cols {
			brightness := u8(20 + int(f32(row) / f32(ls.rows) * 30))
			layer_set(ls, .Background, col, row, Grafel{
				char = '█',
				fg = {brightness, brightness, brightness + 10, 255},
				bg = {brightness, brightness, brightness + 10, 255},
			})
		}
	}

	// Layer 1: World — static shapes
	for col in 5 ..< min(45, ls.cols) {
		for row in 20 ..< min(35, ls.rows) {
			layer_plot(ls, .World, col, row, blue, 0.75)
		}
	}
	for col in 30 ..< min(60, ls.cols) {
		for row in 15 ..< min(30, ls.rows) {
			layer_plot(ls, .World, col, row, green, 0.5)
		}
	}

	// Layer 2: Entity — moving circle
	cx := int(f32(ls.cols) / 2 + math.cos(time) * 15)
	cy := int(f32(ls.rows) / 2 + math.sin(time * 0.7) * 8)
	for row in cy - 4 ..= cy + 4 {
		for col in cx - 4 ..= cx + 4 {
			dx := col - cx
			dy := row - cy
			if dx * dx + dy * dy <= 16 {
				layer_plot(ls, .Entity, col, row, red, 1.0)
			}
		}
	}

	// Layer 3: Effects — pulsing glow around entity
	glow_r := 6 + int(math.sin(time * 3) * 2)
	for row in cy - glow_r ..= cy + glow_r {
		for col in cx - glow_r ..= cx + glow_r {
			dx := col - cx
			dy := row - cy
			dist_sq := dx * dx + dy * dy
			if dist_sq <= glow_r * glow_r && dist_sq > 16 {
				opacity := 1.0 - f32(dist_sq) / f32(glow_r * glow_r)
				layer_plot(ls, .Effects, col, row, yellow, opacity * 0.6, .Additive)
			}
		}
	}

	// Layer 4: UI — text overlay always on top
	// Write directly to UI layer buffer using a temporary grid wrapper
	ui_grid := Grid{
		cells = ls.layers[LayerID.UI],
		cols = ls.cols,
		rows = ls.rows,
		cell_w = grid.cell_w,
		cell_h = grid.cell_h,
		font_size = grid.font_size,
		fidelity = grid.fidelity,
	}
	draw_text(&ui_grid, 2, 1, "LAYERS DEMO", white)
	draw_text(&ui_grid, 2, 7, "BG  WORLD  ENTITY  FX  UI", cyan)

	// Composite and output
	layer_composite(ls)
	layer_to_grid(ls, grid)
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
