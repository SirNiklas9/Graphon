package main

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "core:fmt"
import imgui "lib:odin-imgui"
import rlimgui "lib:imgui_impl_raylib"

INIT_SCREEN_W :: 1920
INIT_SCREEN_H :: 1080
INIT_FONT_SZ  :: i32(1)
FONT_PATH     :: "assets/JetBrainsMonoNLNerdFont-Regular.ttf"

main :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
	rl.InitWindow(INIT_SCREEN_W, INIT_SCREEN_H, "Graphon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(0)
	rl.HideCursor()

	// ImGui
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	rlimgui.init()
	defer rlimgui.shutdown()

	// --- Graphon renderer ---
	g := graphon_init(i32(rl.GetScreenWidth()), i32(rl.GetScreenHeight()), FONT_PATH, INIT_FONT_SZ)
	defer graphon_destroy(&g)

	// --- Scene from .grf ---
	loaded, grf_ok := grf_load_scene("assets/demo.grf")
	if !grf_ok {
		rl.TraceLog(.ERROR, "Failed to load demo.grf — using empty scene")
		loaded.scene = scene_create()
		loaded.scene.camera = camera_create({-8, 6, 14}, {0, 1, 0})
	}
	defer grf_loaded_scene_destroy(&loaded)
	scene := &loaded.scene

	// Orbit light index (second light in the .grf)
	orbit_light_idx := 1

	// Hot reload watcher
	watcher := grf_watcher_create(0.5)
	defer grf_watcher_destroy(&watcher)
	grf_watcher_add(&watcher, "assets/demo.grf")
	grf_watcher_add(&watcher, "assets/voxel_house.grf")

	// Data input API (UDP port 9999) — disabled for now
	// data_in := data_input_create(9999)
	// defer data_input_destroy(&data_in)

	// 2D screen-space overlay
	test_sprite := rl.LoadTexture("assets/test_sprite.png")
	defer rl.UnloadTexture(test_sprite)

	// Fire particles (demo simulation — NOT renderer code)
	MAX_FIRE :: 200
	fire: [MAX_FIRE]RenderParticle
	fire_vel: [MAX_FIRE]rl.Vector3
	fire_life: [MAX_FIRE]f32
	fire_pos := rl.Vector3{5, 0.5, -3}

	time: f32 = 0
	sun_angle: f32 = 0 // horizontal sun angle in radians, 0 = default from .grf

	// Store original directional light elevation for sun rotation
	orig_sun_dist: f32 = 1.0
	orig_sun_elevation: f32 = 0.5
	for i in 0 ..< min(scene.light_count, MAX_SCENE_LIGHTS) {
		if scene.lights[i].enabled && scene.lights[i].type == .Directional {
			d := rl.Vector3{
				scene.lights[i].position.x - scene.lights[i].target.x,
				scene.lights[i].position.y - scene.lights[i].target.y,
				scene.lights[i].position.z - scene.lights[i].target.z,
			}
			orig_sun_dist = math.sqrt(d.x*d.x + d.y*d.y + d.z*d.z)
			if orig_sun_dist > 0.001 {
				orig_sun_elevation = math.asin(clamp(d.y / orig_sun_dist, -1, 1))
				sun_angle = math.atan2(d.z, d.x)
			}
			break
		}
	}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt

		// Window resize
		if rl.IsWindowResized() {
			new_w := i32(rl.GetScreenWidth())
			new_h := i32(rl.GetScreenHeight())
			if new_w > 0 && new_h > 0 {
				g.width = new_w
				g.height = new_h
				graphon_resize_font(&g, g.font_size) // rebuilds grid + render targets
			}
		}

		// Font size
		if rl.IsKeyPressed(.UP)    { graphon_resize_font(&g, g.font_size + 2) }
		if rl.IsKeyPressed(.DOWN)  { graphon_resize_font(&g, g.font_size - 2) }
		if rl.IsKeyPressed(.LEFT)  { graphon_resize_font(&g, g.font_size - 1) }
		if rl.IsKeyPressed(.RIGHT) { graphon_resize_font(&g, g.font_size + 1) }

		// Data input (UDP) — disabled for now
		// data_input_poll(&data_in, scene)

		// Hot reload
		reload_pending := grf_watcher_update(&watcher, dt)

		// Sun controls — [/]: rotate east/west, ;/': raise/lower (time of day)
		if rl.IsKeyDown(.LEFT_BRACKET)  { sun_angle -= dt * 0.5 }
		if rl.IsKeyDown(.RIGHT_BRACKET) { sun_angle += dt * 0.5 }
		if rl.IsKeyDown(.APOSTROPHE)    { orig_sun_elevation = min(orig_sun_elevation + dt * 0.3, math.PI * 0.48) }
		if rl.IsKeyDown(.SEMICOLON)     { orig_sun_elevation = max(orig_sun_elevation - dt * 0.3, -0.05) }
		// Update directional light from sun angle + elevation
		for i in 0 ..< scene.light_count {
			if scene.lights[i].type == .Directional {
				horiz := math.cos(orig_sun_elevation) * orig_sun_dist
				scene.lights[i].position = {
					scene.lights[i].target.x + math.cos(sun_angle) * horiz,
					scene.lights[i].target.y + math.sin(orig_sun_elevation) * orig_sun_dist,
					scene.lights[i].target.z + math.sin(sun_angle) * horiz,
				}
				break
			}
		}

		// Camera
		camera_update(&scene.camera, dt)

		// Orbit warm light
		if orbit_light_idx >= 0 && orbit_light_idx < scene.light_count {
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

		// Render scene through Graphon pipeline
		graphon_render_scene(&g, scene, time, nil, fire[:])

		// Controls
		if rl.IsKeyPressed(.F1) { g.config.show_grid_lines = !g.config.show_grid_lines }
		if rl.IsKeyPressed(.F2) { g.config.show_cell_coords = !g.config.show_cell_coords }
		if rl.IsKeyPressed(.F3) { g.scene3d.sky_night_mode = !g.scene3d.sky_night_mode }
		if rl.IsKeyPressed(.F4) { graphon_toggle_fx(&g, .Bloom) }
		if rl.IsKeyPressed(.F5) { graphon_toggle_fx(&g, .Scanlines) }
		if rl.IsKeyPressed(.F6) { graphon_toggle_fx(&g, .Chromatic) }
		if rl.IsKeyPressed(.F7) {
			g.grid.forced_fidelity = !g.grid.forced_fidelity
			if !g.grid.forced_fidelity {
				// Recompute from cell size instead of hardcoding .ALL
				g.grid.fidelity = fidelity_from_cell_size(min(g.grid.cell_w, g.grid.cell_h))
			}
		}
		if rl.IsKeyPressed(.F8) && g.grid.forced_fidelity {
			g.grid.fidelity = Fidelity((int(g.grid.fidelity) + 1) % 5)
		}
		if rl.IsKeyPressed(.F11) { rl.ToggleBorderlessWindowed() }
		if rl.IsKeyPressed(.F12) { export_screenshot() }


		// 2D screen-space sprite (bottom-right corner)
		rl.DrawTexture(test_sprite, rl.GetScreenWidth() - test_sprite.width - 20, rl.GetScreenHeight() - test_sprite.height - 20, rl.WHITE)

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
			fx_buf: [64]u8
			bloom_str := .Bloom in g.gpu.active_fx ? "ON" : "off"
			scan_str := .Scanlines in g.gpu.active_fx ? "ON" : "off"
			chrom_str := .Chromatic in g.gpu.active_fx ? "ON" : "off"
			fmt.bprintf(fx_buf[:], "FX: B:%s S:%s C:%s\x00", bloom_str, scan_str, chrom_str)
			imgui.Text(cstring(raw_data(fx_buf[:])))

			fid_names := [Fidelity]cstring{.FULL_ONLY = "FULL_ONLY", .DENSITY = "DENSITY", .HALF = "HALF", .FRACTIONAL = "FRACTIONAL", .ALL = "ALL"}
			fid_buf: [48]u8
			fmt.bprintf(fid_buf[:], "Fidelity: %s (%s)\x00", fid_names[g.grid.fidelity], g.grid.forced_fidelity ? "forced" : "auto")
			imgui.Text(cstring(raw_data(fid_buf[:])))

			imgui.Separator()
			sun_buf: [64]u8
			sun_deg := sun_angle * 57.2958
			sun_elev := orig_sun_elevation * 57.2958
			fmt.bprintf(sun_buf[:], "Sun: %.0f deg  %.0f elev\x00", sun_deg, sun_elev)
			imgui.Text(cstring(raw_data(sun_buf[:])))
			imgui.Text("[/]:Rotate  ;/':Elevate")

			imgui.Separator()
			imgui.Separator()
			imgui.Text("WASD:Move  RMB:Look  QE:Up/Down")
			imgui.Text("F3:Night F4:Bloom F5:Scan F6:Chrom")
		}
		imgui.End()
		rlimgui.end()

		// Re-hide cursor after ImGui (it re-enables it each frame)
		if !rl.IsCursorOnScreen() || true {
			rl.HideCursor()
		}

		// Custom cursor — drawn last, always on top
		mp := rl.GetMousePosition()
		mx := i32(mp.x)
		my := i32(mp.y)
		// Arrow shape
		rl.DrawTriangle({f32(mx), f32(my)}, {f32(mx), f32(my + 16)}, {f32(mx + 12), f32(my + 12)}, rl.WHITE)
		rl.DrawTriangleLines({f32(mx), f32(my)}, {f32(mx), f32(my + 16)}, {f32(mx + 12), f32(my + 12)}, {40, 40, 40, 255})

		rl.EndDrawing()

		// Hot reload — after frame is fully complete
		if reload_pending {
			new_loaded, new_ok := grf_load_scene("assets/demo.grf")
			if new_ok {
				// Reset Scene3D light/volume state before destroying old scene
				g.scene3d.light_count = 0
				g.scene3d.volume_count = 0
				grf_loaded_scene_destroy(&loaded)
				loaded = new_loaded
				scene = &loaded.scene
				// Re-sync lights and volumes from new scene
				scene3d_apply_scene(&g.scene3d, scene)
				rl.TraceLog(.INFO, "Scene reloaded successfully")
			}
		}
	}
}

load_font :: proc(size: i32) -> rl.Font {
	codepoints := ALL_CODEPOINTS
	font := rl.LoadFontEx(FONT_PATH, size, raw_data(codepoints[:]), i32(len(codepoints)))
	rl.SetTextureFilter(font.texture, .POINT)
	return font
}
