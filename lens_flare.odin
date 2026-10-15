package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"
import "core:math/linalg"

// Raw GL for depth readback (opengl32.dll — no extension loading needed)
GL_DEPTH_COMPONENT :: 0x1902
GL_FLOAT           :: 0x1406

when ODIN_OS == .Windows {
	foreign import opengl "system:opengl32.lib"

	@(default_calling_convention = "stdcall")
	foreign opengl {
		glReadPixels :: proc(x, y, width, height: i32, format, type: u32, pixels: rawptr) ---
	}
} else when ODIN_OS == .Linux {
	foreign import opengl "system:GL"

	foreign opengl {
		glReadPixels :: proc(x, y, width, height: i32, format, type: u32, pixels: rawptr) ---
	}
}

// Ghost element — positioned along the line from light source through screen center
LensFlareGhost :: struct {
	t:     f32,
	size:  f32,
	alpha: f32,
	color: rl.Color,
	ring:  bool,
	sides: i32,
}

FLARE_GHOSTS :: [10]LensFlareGhost{
	{t = 0.15, size = 0.008, alpha = 0.12, color = {255, 200, 120, 255}, ring = false, sides = 6},
	{t = 0.30, size = 0.015, alpha = 0.06, color = {200, 220, 255, 255}, ring = true,  sides = 0},
	{t = 0.50, size = 0.025, alpha = 0.05, color = {120, 180, 255, 255}, ring = true,  sides = 0},
	{t = 0.65, size = 0.010, alpha = 0.08, color = {180, 255, 180, 255}, ring = false, sides = 6},
	{t = 0.80, size = 0.035, alpha = 0.04, color = {255, 180, 100, 255}, ring = true,  sides = 0},
	{t = 1.00, size = 0.012, alpha = 0.07, color = {200, 200, 255, 255}, ring = false, sides = 0},
	{t = 1.20, size = 0.040, alpha = 0.03, color = {140, 160, 255, 255}, ring = true,  sides = 0},
	{t = 1.40, size = 0.018, alpha = 0.05, color = {255, 200, 140, 255}, ring = false, sides = 6},
	{t = 1.60, size = 0.050, alpha = 0.025,color = {100, 140, 255, 255}, ring = true,  sides = 0},
	{t = 1.80, size = 0.014, alpha = 0.04, color = {180, 255, 200, 255}, ring = false, sides = 0},
}

// Depth-based occlusion for lens flare
FlareOcclusion :: struct {
	occlusion:   f32,   // smoothed 0-1 visibility
	initialized: bool,
}

flare_occlusion_init :: proc(fo: ^FlareOcclusion) {
	fo.occlusion = 1.0
	fo.initialized = true
}

flare_occlusion_destroy :: proc(fo: ^FlareOcclusion) {
	fo.initialized = false
}

// Read depth buffer at the sun's screen position and compare to determine occlusion.
// Call AFTER geometry is drawn but BEFORE EndMode3D (depth buffer must be current).
flare_occlusion_update :: proc(fo: ^FlareOcclusion, sun_screen: rl.Vector2) {
	if !fo.initialized do return

	w := i32(rl.GetScreenWidth())
	h := i32(rl.GetScreenHeight())

	// Flip Y: Raylib is top-left origin, GL is bottom-left origin
	sx := clamp(i32(sun_screen.x), 0, w - 1)
	sy := clamp(h - 1 - i32(sun_screen.y), 0, h - 1)

	// Flush batch so depth buffer is up to date
	rlgl.DrawRenderBatchActive()

	// Read 1 pixel of depth at sun's projected position
	depth: f32
	glReadPixels(sx, sy, 1, 1, GL_DEPTH_COMPONENT, GL_FLOAT, &depth)

	// If depth buffer value >= sun's depth, nothing is blocking
	// (depth buffer has 1.0 where only sky is drawn)
	target: f32 = depth >= 0.999 ? 1.0 : 0.0  // sky = 1.0 (nothing written), geometry < 1.0

	speed := f32(20.0) * rl.GetFrameTime()
	fo.occlusion += (target - fo.occlusion) * clamp(speed, 0, 1)
}

// Draw lens flare effects for all enabled directional lights.
// 2D screen-space effect — call after EndMode3D but before EndTextureMode.
draw_lens_flares :: proc(s: ^Scene3D, cam: ^Camera) {
	screen_w := f32(rl.GetScreenWidth())
	screen_h := f32(rl.GetScreenHeight())
	center := rl.Vector2{screen_w * 0.5, screen_h * 0.5}
	max_dist := math.sqrt(center.x * center.x + center.y * center.y)

	for i in 0 ..< s.light_count {
		light := &s.lights[i]
		if !light.enabled do continue
		if light.type != .Directional do continue

		light_dir := linalg.normalize(rl.Vector3{
			light.position.x - light.target.x,
			light.position.y - light.target.y,
			light.position.z - light.target.z,
		})

		// Skip if sun is behind camera
		view_dir := linalg.normalize(cam.rl_cam.target - cam.rl_cam.position)
		view_dot := linalg.dot(light_dir, view_dir)
		if view_dot <= 0.1 do continue

		// Project sun position to screen
		far_point := cam.rl_cam.position + light_dir * 200
		screen_pos := rl.GetWorldToScreen(far_point, cam.rl_cam)

		// Only show flare when sun is reasonably on-screen
		if screen_pos.x < -100 || screen_pos.x > screen_w + 100 do continue
		if screen_pos.y < -100 || screen_pos.y > screen_h + 100 do continue

		// Occlusion
		occ := s.flare_occlusion.initialized ? s.flare_occlusion.occlusion : f32(1.0)

		// Intensity — stronger when looking directly at the sun
		view_alignment := clamp((view_dot - 0.1) / 0.9, 0, 1) // 0 at edge, 1 looking straight at sun
		intensity := view_alignment * view_alignment // quadratic falloff from center
		intensity *= occ

		if intensity < 0.005 do continue

		rlgl.DrawRenderBatchActive()
		rlgl.SetBlendMode(i32(rl.BlendMode.ADDITIVE))

		// --- Sun glow ---
		rl.DrawCircleV(screen_pos, 50 * intensity + 15, {255, 220, 180, u8(clamp(intensity * 30, 0, 255))})
		rl.DrawCircleV(screen_pos, 20 * intensity + 6,  {255, 240, 210, u8(clamp(intensity * 60, 0, 255))})
		rl.DrawCircleV(screen_pos, 6 * intensity + 2,   {255, 255, 240, u8(clamp(intensity * 120, 0, 255))})
		rl.DrawCircleV(screen_pos, 3, {255, 255, 255, u8(clamp(intensity * 200, 0, 255))})

		// --- Anamorphic streak ---
		streak_len := screen_h * 0.4 * intensity
		for si in 0 ..< 5 {
			angle := f32(si - 2) * 0.015
			cos_a := math.cos(angle)
			sin_a := math.sin(angle)
			s_len := streak_len * (1.0 - f32(abs(si - 2)) * 0.2)
			s_alpha := u8(clamp(intensity * 100 * (1.0 - f32(abs(si - 2)) * 0.3), 0, 255))
			thickness := 3.0 - f32(abs(si - 2)) * 0.8
			if s_alpha < 1 do continue
			rl.DrawLineEx(
				{screen_pos.x - cos_a * s_len, screen_pos.y - sin_a * s_len},
				{screen_pos.x + cos_a * s_len, screen_pos.y + sin_a * s_len},
				thickness,
				{255, 245, 230, s_alpha},
			)
		}

		// --- Ghost chain ---
		for ghost in FLARE_GHOSTS {
			gx := screen_pos.x + (center.x - screen_pos.x) * ghost.t
			gy := screen_pos.y + (center.y - screen_pos.y) * ghost.t
			gpos := rl.Vector2{gx, gy}

			ghost_size := ghost.size * screen_h * (0.6 + intensity * 0.4)

			ghost_dist := math.sqrt((gx - center.x) * (gx - center.x) + (gy - center.y) * (gy - center.y))
			edge_fade := clamp(1.0 - ghost_dist / max_dist * 0.5, 0.2, 1.0)
			ga := u8(clamp(ghost.alpha * intensity * edge_fade * 255, 0, 255))
			if ga < 1 do continue

			gc := rl.Color{ghost.color.r, ghost.color.g, ghost.color.b, ga}

			if ghost.ring {
				ring_thickness := max(ghost_size * 0.2, 2.0)
				steps := i32(max(ghost_size * 2, 24))
				if ghost.sides > 0 {
					rl.DrawPolyLinesEx(gpos, ghost.sides, ghost_size, 0, ring_thickness, gc)
				} else {
					rl.DrawRing(gpos, ghost_size - ring_thickness, ghost_size, 0, 360, steps, gc)
				}
			} else {
				if ghost.sides > 0 {
					rl.DrawPoly(gpos, ghost.sides, ghost_size, 30, gc)
				} else {
					rl.DrawCircleV(gpos, ghost_size, gc)
				}
			}
		}

		rlgl.DrawRenderBatchActive()
		rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
	}
}
