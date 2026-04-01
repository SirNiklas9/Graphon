package main

import rl "vendor:raylib"

// Top-level Graphon rendering context — owns all rendering state
Graphon :: struct {
	grid:      Grid,
	gpu_grid:  GPUGrid,
	gpu:       GPUPipeline,
	scene3d:   Scene3D,
	font:      rl.Font,
	font_size: i32,
	config:    Config,
	width:     i32,
	height:    i32,
}

graphon_init :: proc(width, height: i32, font_path: cstring, font_size: i32 = 20) -> Graphon {
	g := Graphon{
		width     = width,
		height    = height,
		font_size = font_size,
		config    = config_default(),
	}

	g.font = load_font(font_size)
	grid_init(&g.grid, width, height, g.font, font_size)
	g.gpu_grid = gpu_grid_create(g.grid.cols, g.grid.rows)
	g.gpu = gpu_create(width, height)
	g.scene3d = scene3d_create(g.grid.cols, g.grid.rows)

	return g
}

graphon_destroy :: proc(g: ^Graphon) {
	scene3d_destroy(&g.scene3d)
	gpu_destroy(&g.gpu)
	gpu_grid_destroy(&g.gpu_grid)
	grid_destroy(&g.grid)
	rl.UnloadFont(g.font)
}

graphon_resize_font :: proc(g: ^Graphon, new_size: i32) {
	size := clamp(new_size, 1, 64)
	rl.UnloadFont(g.font)
	g.font = load_font(size)
	g.font_size = size
	grid_resize(&g.grid, g.width, g.height, g.font, size)
	gpu_grid_resize(&g.gpu_grid, g.grid.cols, g.grid.rows)
	scene3d_resize(&g.scene3d, g.grid.cols, g.grid.rows)
}

// Render a 3D scene through the Graphon pipeline
// draw_fn: optional callback for custom primitives (ground, cubes, cylinders, etc.)
// Leaves BeginDrawing open for caller to draw overlays (ImGui, cursor, etc.) before EndDrawing
graphon_render_scene :: proc(g: ^Graphon, scene: ^Scene, time: f32, draw_fn: proc(^Scene3D, bool) = nil, particles: []RenderParticle = nil) {
	// Sync scene data (lights, volumes, fog) to renderer
	scene3d_apply_scene(&g.scene3d, scene)

	// Apply scene fog settings to config (scene overrides defaults)
	if scene.fog_enabled {
		g.config.fog_enabled = true
		g.config.fog_color = {scene.fog_color.x, scene.fog_color.y, scene.fog_color.z}
		g.config.fog_start = scene.fog_start
		g.config.fog_end = scene.fog_end
	}

	// Render 3D scene
	scene3d_render(&g.scene3d, &scene.camera, scene.objects[:scene.object_count], time, draw_fn, &g.config, particles)

	// Get output texture (with SSAO if enabled)
	output := scene3d_get_output(&g.scene3d)

	// Display through Graphon grid
	use_postfx := gpu_has_fx(&g.gpu)
	if use_postfx {
		gpu_begin(&g.gpu)
	} else {
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
	}

	gpu_grid_render(&g.gpu_grid, &g.grid, g.font, true, output, g.grid.cols, g.grid.rows, &g.config)

	// Debug overlays
	if g.config.show_grid_lines { debug_grid_lines(&g.grid, g.grid.cols, g.grid.rows) }
	if g.config.show_cell_coords { debug_cell_coords(&g.grid, g.font, g.grid.cols, g.grid.rows) }

	if use_postfx {
		gpu_end(&g.gpu)
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		gpu_present(&g.gpu, time)
	}
}

// Toggle a post-process effect
graphon_toggle_fx :: proc(g: ^Graphon, fx: PostFXFlag) {
	gpu_toggle_fx(&g.gpu, fx)
}
