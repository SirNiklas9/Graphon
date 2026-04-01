package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"

// Ghost element — positioned along the line from light source through screen center
// t=0 is at the light, t=1 is at screen center, t>1 is past center (reflected)
LensFlareGhost :: struct {
	t:     f32,       // position along flare line
	size:  f32,       // radius relative to screen height (0.01 = 1% of screen)
	alpha: f32,       // opacity (0-1)
	color: rl.Color,  // tint (chromatic shift)
	ring:  bool,      // true = ring outline, false = filled disc
	sides: i32,       // 0 = circle, 4/6/8 = polygon
}

// Physically-motivated ghost chain — simulates internal reflections between lens elements
// Each ghost has a unique chromatic tint from dispersion
FLARE_GHOSTS :: [10]LensFlareGhost{
	// Near-source ghosts (subtle, warm)
	{t = 0.15, size = 0.008, alpha = 0.12, color = {255, 200, 120, 255}, ring = false, sides = 6},
	{t = 0.30, size = 0.015, alpha = 0.06, color = {200, 220, 255, 255}, ring = true,  sides = 0},
	// Mid-field ghosts (chromatic spread)
	{t = 0.50, size = 0.025, alpha = 0.05, color = {120, 180, 255, 255}, ring = true,  sides = 0},
	{t = 0.65, size = 0.010, alpha = 0.08, color = {180, 255, 180, 255}, ring = false, sides = 6},
	{t = 0.80, size = 0.035, alpha = 0.04, color = {255, 180, 100, 255}, ring = true,  sides = 0},
	// Center crossing
	{t = 1.00, size = 0.012, alpha = 0.07, color = {200, 200, 255, 255}, ring = false, sides = 0},
	// Past-center reflections (mirrored, larger, fainter)
	{t = 1.20, size = 0.040, alpha = 0.03, color = {140, 160, 255, 255}, ring = true,  sides = 0},
	{t = 1.40, size = 0.018, alpha = 0.05, color = {255, 200, 140, 255}, ring = false, sides = 6},
	{t = 1.60, size = 0.050, alpha = 0.025,color = {100, 140, 255, 255}, ring = true,  sides = 0},
	{t = 1.80, size = 0.014, alpha = 0.04, color = {180, 255, 200, 255}, ring = false, sides = 0},
}

// Sun occlusion — checked geometrically against scene objects
sun_occlusion: f32 = 1.0

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

		// Light direction (from target toward position = toward the sun)
		light_dir := rl.Vector3{
			light.position.x - light.target.x,
			light.position.y - light.target.y,
			light.position.z - light.target.z,
		}
		len := math.sqrt(light_dir.x*light_dir.x + light_dir.y*light_dir.y + light_dir.z*light_dir.z)
		if len < 0.001 do continue
		light_dir = {light_dir.x/len, light_dir.y/len, light_dir.z/len}

		// Dot with view direction — skip if sun is behind camera
		view_dir := rl.Vector3{
			cam.rl_cam.target.x - cam.rl_cam.position.x,
			cam.rl_cam.target.y - cam.rl_cam.position.y,
			cam.rl_cam.target.z - cam.rl_cam.position.z,
		}
		view_dot := light_dir.x*view_dir.x + light_dir.y*view_dir.y + light_dir.z*view_dir.z
		if view_dot <= 0 do continue

		// Project sun position to screen
		far_point := rl.Vector3{
			cam.rl_cam.position.x + light_dir.x * 200,
			cam.rl_cam.position.y + light_dir.y * 200,
			cam.rl_cam.position.z + light_dir.z * 200,
		}
		screen_pos := rl.GetWorldToScreen(far_point, cam.rl_cam)

		if screen_pos.x < -200 || screen_pos.x > screen_w + 200 do continue
		if screen_pos.y < -200 || screen_pos.y > screen_h + 200 do continue

		// Occlusion — check if sun direction is blocked by the ground or below horizon
		// Sun below ground plane = fully occluded
		if light_dir.y <= 0.0 {
			sun_occlusion = max(sun_occlusion - rl.GetFrameTime() * 4.0, 0.0)
		} else {
			sun_occlusion = min(sun_occlusion + rl.GetFrameTime() * 4.0, 1.0)
		}

		// Intensity based on how centered the sun is + how much it's in view
		dx := screen_pos.x - center.x
		dy := screen_pos.y - center.y
		dist := math.sqrt(dx * dx + dy * dy)
		intensity := clamp(1.0 - (dist / max_dist) * 0.7, 0.0, 1.0)
		intensity *= clamp(view_dot, 0, 1) // Fade as sun approaches edge of view
		intensity *= intensity
		intensity *= sun_occlusion // Fade when sun is behind geometry

		if intensity < 0.005 do continue

		rlgl.SetBlendMode(i32(rl.BlendMode.ADDITIVE))

		// --- Sun glow (layered circles, largest first) ---
		// Outer soft halo
		halo_a := u8(clamp(intensity * 15, 0, 255))
		rl.DrawCircleV(screen_pos, screen_h * 0.06 * intensity + 20, {255, 240, 220, halo_a})
		// Mid glow
		mid_a := u8(clamp(intensity * 35, 0, 255))
		rl.DrawCircleV(screen_pos, screen_h * 0.02 * intensity + 8, {255, 250, 240, mid_a})
		// Hot core
		core_a := u8(clamp(intensity * 80, 0, 255))
		rl.DrawCircleV(screen_pos, 4, {255, 255, 255, core_a})

		// --- Anamorphic streak (multiple thin lines at slight angles) ---
		streak_base := screen_h * 0.08 * intensity
		for si in 0 ..< 3 {
			angle := f32(si - 1) * 0.02 // -0.02, 0, +0.02 radians
			cos_a := math.cos(angle)
			sin_a := math.sin(angle)
			s_len := streak_base * (1.0 - f32(abs(si - 1)) * 0.3) // center streak longest
			s_alpha := u8(clamp(intensity * 18 * (1.0 - f32(abs(si - 1)) * 0.4), 0, 255))
			if s_alpha < 1 do continue
			rl.DrawLineEx(
				{screen_pos.x - cos_a * s_len, screen_pos.y - sin_a * s_len},
				{screen_pos.x + cos_a * s_len, screen_pos.y + sin_a * s_len},
				1.5 - f32(abs(si - 1)) * 0.5,
				{255, 245, 230, s_alpha},
			)
		}

		// --- Ghost chain along the flare line ---
		for ghost in FLARE_GHOSTS {
			// Position: interpolate from light source through screen center
			gx := screen_pos.x + (center.x - screen_pos.x) * ghost.t
			gy := screen_pos.y + (center.y - screen_pos.y) * ghost.t
			gpos := rl.Vector2{gx, gy}

			// Size scales with screen height for resolution independence
			ghost_size := ghost.size * screen_h * (0.6 + intensity * 0.4)

			// Alpha scales with intensity and distance from center
			ghost_dist := math.sqrt((gx - center.x) * (gx - center.x) + (gy - center.y) * (gy - center.y))
			edge_fade := clamp(1.0 - ghost_dist / max_dist * 0.5, 0.2, 1.0)
			ga := u8(clamp(ghost.alpha * intensity * edge_fade * 255, 0, 255))
			if ga < 1 do continue

			gc := rl.Color{ghost.color.r, ghost.color.g, ghost.color.b, ga}

			if ghost.ring {
				// Ring — draw as circle outline (multiple radii for thickness)
				ring_thickness := max(ghost_size * 0.15, 1.5)
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

		rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
	}
}
