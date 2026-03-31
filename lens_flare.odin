package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"

// Ghost element along the flare line
LensFlareGhost :: struct {
	t:      f32, // position along light-to-center line (0 = light, 1 = center, >1 = past center)
	size:   f32, // radius in pixels
	alpha:  f32, // base opacity (0-1)
	sides:  i32, // polygon sides (0 = circle via DrawCircleV)
}

// Default ghost configuration
FLARE_GHOSTS :: [6]LensFlareGhost{
	{t = 0.2, size = 12, alpha = 0.15, sides = 6},
	{t = 0.4, size = 8,  alpha = 0.12, sides = 0},
	{t = 0.6, size = 18, alpha = 0.10, sides = 4},
	{t = 0.8, size = 6,  alpha = 0.14, sides = 0},
	{t = 1.0, size = 14, alpha = 0.08, sides = 6},
	{t = 1.2, size = 10, alpha = 0.06, sides = 0},
}

// Draw lens flare effects for all enabled directional lights.
// This is a 2D screen-space effect — call after EndMode3D but before EndTextureMode.
draw_lens_flares :: proc(s: ^Scene3D, cam: ^Camera) {
	screen_w := f32(rl.GetScreenWidth())
	screen_h := f32(rl.GetScreenHeight())
	center := rl.Vector2{screen_w * 0.5, screen_h * 0.5}
	max_dist := math.sqrt(center.x * center.x + center.y * center.y)

	for i in 0 ..< s.light_count {
		light := &s.lights[i]
		if !light.enabled do continue
		if light.type != .Directional do continue

		// Directional light: project a point far along the light direction from camera
		// The light "source" is infinitely far — place it 200 units from camera in the light direction
		light_dir := rl.Vector3{
			light.position.x - light.target.x,
			light.position.y - light.target.y,
			light.position.z - light.target.z,
		}
		len := math.sqrt(light_dir.x*light_dir.x + light_dir.y*light_dir.y + light_dir.z*light_dir.z)
		if len < 0.001 do continue
		light_dir = {light_dir.x/len, light_dir.y/len, light_dir.z/len}
		far_point := rl.Vector3{
			cam.rl_cam.position.x + light_dir.x * 200,
			cam.rl_cam.position.y + light_dir.y * 200,
			cam.rl_cam.position.z + light_dir.z * 200,
		}
		screen_pos := rl.GetWorldToScreen(far_point, cam.rl_cam)

		// Skip if the light is behind the camera (off-screen)
		if screen_pos.x < -100 || screen_pos.x > screen_w + 100 do continue
		if screen_pos.y < -100 || screen_pos.y > screen_h + 100 do continue

		// Intensity scales down as the light moves toward screen edges
		dx := screen_pos.x - center.x
		dy := screen_pos.y - center.y
		dist := math.sqrt(dx * dx + dy * dy)
		intensity := clamp(1.0 - (dist / max_dist), 0.0, 1.0)
		intensity *= intensity // quadratic falloff for subtlety

		if intensity < 0.01 do continue

		// Light color as u8 for drawing
		lr := u8(light.color.x * 255)
		lg := u8(light.color.y * 255)
		lb := u8(light.color.z * 255)

		// Enable additive blending
		rlgl.SetBlendMode(i32(rl.BlendMode.ADDITIVE))

		// --- Central glow at light position ---
		// Soft outer glow
		glow_alpha := u8(clamp(intensity * 40, 0, 255))
		rl.DrawCircleV(screen_pos, 48 * intensity + 8, {lr, lg, lb, glow_alpha})
		// Brighter inner core
		core_alpha := u8(clamp(intensity * 80, 0, 255))
		rl.DrawCircleV(screen_pos, 16 * intensity + 3, {lr, lg, lb, core_alpha})
		// Tiny bright center
		hot_alpha := u8(clamp(intensity * 140, 0, 255))
		rl.DrawCircleV(screen_pos, 4, {255, 255, 255, hot_alpha})

		// --- Anamorphic streak (horizontal line through the light) ---
		streak_len := 80 * intensity
		streak_alpha := u8(clamp(intensity * 30, 0, 255))
		rl.DrawLineEx(
			{screen_pos.x - streak_len, screen_pos.y},
			{screen_pos.x + streak_len, screen_pos.y},
			2,
			{lr, lg, lb, streak_alpha},
		)

		// --- Ghost elements along the flare line ---
		for ghost in FLARE_GHOSTS {
			// Interpolate position: 0 = light, 1 = center
			gx := screen_pos.x + (center.x - screen_pos.x) * ghost.t
			gy := screen_pos.y + (center.y - screen_pos.y) * ghost.t
			gpos := rl.Vector2{gx, gy}

			// Scale alpha by overall intensity
			ga := u8(clamp(ghost.alpha * intensity * 255, 0, 255))
			if ga < 1 do continue

			ghost_color := rl.Color{lr, lg, lb, ga}
			ghost_size := ghost.size * (0.5 + intensity * 0.5)

			if ghost.sides == 0 {
				// Circle
				rl.DrawCircleV(gpos, ghost_size, ghost_color)
			} else {
				// Polygon (diamond for 4, hexagon for 6)
				rl.DrawPoly(gpos, ghost.sides, ghost_size, 0, ghost_color)
			}
		}

		// Restore default blend mode
		rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
	}
}
