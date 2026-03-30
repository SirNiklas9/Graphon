package main

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "core:fmt"
import imgui "lib:odin-imgui"
import rlimgui "lib:imgui_impl_raylib"

SCREEN_W     :: 1920
SCREEN_H     :: 1080
INIT_FONT_SZ :: i32(1)
FONT_PATH    :: "assets/JetBrainsMonoNLNerdFont-Regular.ttf"

// Demo draw callback — custom primitives
demo_draw :: proc(s3d: ^Scene3D, use_shader: bool) {
	// Ground — only in color pass
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
	rl.HideCursor()

	// ImGui
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	rlimgui.init()
	defer rlimgui.shutdown()

	// --- Graphon renderer ---
	g := graphon_init(SCREEN_W, SCREEN_H, FONT_PATH, INIT_FONT_SZ)
	defer graphon_destroy(&g)

	// --- Scene ---
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
	scene.objects[scene.object_count - 1].auto_rotate = true
	scene.objects[scene.object_count - 1].rotate_speed = 0.5

	// Fire particles (demo simulation — NOT renderer code)
	MAX_FIRE :: 200
	fire: [MAX_FIRE]RenderParticle
	fire_vel: [MAX_FIRE]rl.Vector3
	fire_life: [MAX_FIRE]f32
	fire_pos := rl.Vector3{5, 0.5, -3}

	time: f32 = 0

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt

		// Font size
		if rl.IsKeyPressed(.UP)    { graphon_resize_font(&g, g.font_size + 2) }
		if rl.IsKeyPressed(.DOWN)  { graphon_resize_font(&g, g.font_size - 2) }
		if rl.IsKeyPressed(.LEFT)  { graphon_resize_font(&g, g.font_size - 1) }
		if rl.IsKeyPressed(.RIGHT) { graphon_resize_font(&g, g.font_size + 1) }

		// Camera
		camera_update(&scene.camera, dt)

		// Orbit warm light
		if orbit_light_idx >= 0 {
			scene.lights[orbit_light_idx].position = {
				math.cos(time * 0.5) * 6,
				2.5,
				math.sin(time * 0.5) * 6,
			}
		}

		// Fire simulation (demo code)
		for i in 0 ..< MAX_FIRE {
			fire_life[i] -= dt
			if fire_life[i] <= 0 {
				fire[i].position = fire_pos
				fire[i].position.x += (rand.float32() - 0.5) * 0.8
				fire[i].position.z += (rand.float32() - 0.5) * 0.8
				fire_vel[i] = {(rand.float32() - 0.5) * 0.5, 1.5 + rand.float32() * 2, (rand.float32() - 0.5) * 0.5}
				fire_life[i] = 0.5 + rand.float32() * 1.0
				fire[i].size = 0.3 + rand.float32() * 0.4
			}
			fire[i].position.x += fire_vel[i].x * dt
			fire[i].position.y += fire_vel[i].y * dt
			fire[i].position.z += fire_vel[i].z * dt
			t := clamp(fire_life[i] / 1.5, 0, 1)
			fire[i].color = {u8(255 * t), u8(120 * t * t), u8(20 * t * t * t), u8(200 * t)}
			fire[i].size *= 0.998
		}

		// Sync lights to renderer
		g.scene3d.light_count = 0
		for i in 0 ..< scene.light_count {
			l := &scene.lights[i]
			scene3d_add_light(&g.scene3d, l.type, l.position, l.target, l.color)
		}

		// Render scene
		scene3d_render(&g.scene3d, &scene.camera, scene.objects[:scene.object_count], time, demo_draw, &g.config, fire[:])

		// Display
		use_postfx := g.gpu.active_fx != .None
		if use_postfx { gpu_begin(&g.gpu) }
		else { rl.BeginDrawing(); rl.ClearBackground(rl.BLACK) }

		output := scene3d_get_output(&g.scene3d)
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

		// Controls
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
		if rl.IsKeyPressed(.F11) { rl.ToggleBorderlessWindowed() }
		if rl.IsKeyPressed(.F12) { export_screenshot() }

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
			imgui.Text("WASD:Move  RMB:Look  QE:Up/Down")
			imgui.Text("F4:PostFX  F7:Fidelity  F12:Screenshot")
		}
		imgui.End()
		rlimgui.end()

		// Custom cursor — drawn last, always on top
		mp := rl.GetMousePosition()
		mx := i32(mp.x)
		my := i32(mp.y)
		// Arrow shape
		rl.DrawTriangle({f32(mx), f32(my)}, {f32(mx), f32(my + 16)}, {f32(mx + 12), f32(my + 12)}, rl.WHITE)
		rl.DrawTriangleLines({f32(mx), f32(my)}, {f32(mx), f32(my + 16)}, {f32(mx + 12), f32(my + 12)}, {40, 40, 40, 255})

		rl.EndDrawing()
	}
}

load_font :: proc(size: i32) -> rl.Font {
	codepoints := ALL_CODEPOINTS
	font := rl.LoadFontEx(FONT_PATH, size, raw_data(codepoints[:]), i32(len(codepoints)))
	rl.SetTextureFilter(font.texture, .POINT)
	return font
}
