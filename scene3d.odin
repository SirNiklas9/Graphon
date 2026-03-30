package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"
import "core:math/linalg"

MAX_LIGHTS :: 4

LightType :: enum i32 {
	Directional = 0,
	Point       = 1,
}

Light :: struct {
	enabled:  bool,
	type:     LightType,
	position: rl.Vector3,
	target:   rl.Vector3,
	color:    rl.Vector3, // normalized 0-1 RGB

	// Shader uniform locations (per-light)
	enabled_loc:  i32,
	type_loc:     i32,
	position_loc: i32,
	target_loc:   i32,
	color_loc:    i32,
}

// GPU 3D scene renderer — uses Raylib's native 3D pipeline to render models,
// then captures the output for the Grafel glyph shader
Scene3D :: struct {
	target:  rl.RenderTexture2D,
	cols:    int,
	rows:    int,
	enabled: bool,
	shader:  rl.Shader,

	// Global uniform locations
	ambient_loc:          i32,
	view_pos_loc:         i32,
	shadow_enabled_loc:   i32,
	shadow_light_idx_loc: i32,
	shadow_map_res_loc:   i32,
	has_normal_map_loc:   i32,
	normal_map_loc:       i32,
	fog_color_loc:        i32,
	fog_start_loc:        i32,
	fog_end_loc:          i32,
	fog_enabled_loc:      i32,
	volume_locs:          [4][5]i32, // [vol_idx][minPos, maxPos, color, density, enabled]

	// Shadow map
	shadow: ShadowMap,

	// Sky
	sky_shader:        rl.Shader,
	sky_vp_loc:        i32,
	sky_sun_dir_loc:   i32,

	// Depth pass + SSAO
	depth_shader:      rl.Shader,
	depth_target:      rl.RenderTexture2D,
	depth_vp_loc:      i32,
	ssao_shader:       rl.Shader,
	ssao_target:       rl.RenderTexture2D,
	ssao_res_loc:      i32,
	ssao_radius_loc:   i32,
	ssao_strength_loc: i32,
	ssao_depth_loc:    i32,
	ssao_enabled:      bool,

	// Lights
	lights:     [MAX_LIGHTS]Light,
	light_count: int,
}

scene3d_create :: proc(cols, rows: int) -> Scene3D {
	// Render at full screen resolution — prevents aliasing/moiré on upscale
	c := int(rl.GetScreenWidth())
	r := int(rl.GetScreenHeight())

	target := rl.LoadRenderTexture(i32(c), i32(r))

	// Load lighting shader
	shader := rl.LoadShader("assets/lighting.vs", "assets/lighting.fs")

	// Set matModel and matNormal shader locations so Raylib passes them
	shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocation(shader, "matModel")
	shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL] = rl.GetShaderLocation(shader, "matNormal")

	s := Scene3D{
		target             = target,
		cols               = c,
		rows               = r,
		enabled            = true,
		shader             = shader,
		ambient_loc        = rl.GetShaderLocation(shader, "ambientColor"),
		view_pos_loc       = rl.GetShaderLocation(shader, "viewPos"),
		shadow_enabled_loc     = rl.GetShaderLocation(shader, "shadowEnabled"),
		shadow_light_idx_loc   = rl.GetShaderLocation(shader, "shadowLightIdx"),
		shadow_map_res_loc     = rl.GetShaderLocation(shader, "shadowMapResolution"),
		has_normal_map_loc     = rl.GetShaderLocation(shader, "hasNormalMap"),
		normal_map_loc         = rl.GetShaderLocation(shader, "normalMap"),
		fog_color_loc          = rl.GetShaderLocation(shader, "fogColor"),
		fog_start_loc          = rl.GetShaderLocation(shader, "fogStart"),
		fog_end_loc            = rl.GetShaderLocation(shader, "fogEnd"),
		fog_enabled_loc        = rl.GetShaderLocation(shader, "fogEnabled"),
		shadow                 = shadow_create(),
		ssao_enabled           = true,
	}

	// Cache volume uniform locations
	for i in 0 ..< 4 {
		idx := i32(i)
		s.volume_locs[i][0] = rl.GetShaderLocation(shader, rl.TextFormat("volumes[%d].minPos", idx))
		s.volume_locs[i][1] = rl.GetShaderLocation(shader, rl.TextFormat("volumes[%d].maxPos", idx))
		s.volume_locs[i][2] = rl.GetShaderLocation(shader, rl.TextFormat("volumes[%d].color", idx))
		s.volume_locs[i][3] = rl.GetShaderLocation(shader, rl.TextFormat("volumes[%d].density", idx))
		s.volume_locs[i][4] = rl.GetShaderLocation(shader, rl.TextFormat("volumes[%d].enabled", idx))
	}

	// Cache per-light uniform locations
	for i in 0 ..< MAX_LIGHTS {
		idx := i32(i)
		s.lights[i].enabled_loc  = rl.GetShaderLocation(shader, rl.TextFormat("lights[%d].enabled", idx))
		s.lights[i].type_loc     = rl.GetShaderLocation(shader, rl.TextFormat("lights[%d].type", idx))
		s.lights[i].position_loc = rl.GetShaderLocation(shader, rl.TextFormat("lights[%d].position", idx))
		s.lights[i].target_loc   = rl.GetShaderLocation(shader, rl.TextFormat("lights[%d].target", idx))
		s.lights[i].color_loc    = rl.GetShaderLocation(shader, rl.TextFormat("lights[%d].color", idx))
	}

	// Sky shader
	s.sky_shader = rl.LoadShader("assets/lighting.vs", "assets/sky.fs")
	if s.sky_shader.id != 0 {
		s.sky_shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocation(s.sky_shader, "matModel")
		s.sky_shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL] = rl.GetShaderLocation(s.sky_shader, "matNormal")
		s.sky_vp_loc = rl.GetShaderLocation(s.sky_shader, "viewPos")
		s.sky_sun_dir_loc = rl.GetShaderLocation(s.sky_shader, "sunDirection")
	}

	// Depth pass — float-precision texture to avoid banding in SSAO
	s.depth_shader = rl.LoadShader("assets/lighting.vs", "assets/depth_output.fs")
	if s.depth_shader.id != 0 {
		s.depth_shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocation(s.depth_shader, "matModel")
		s.depth_shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL] = rl.GetShaderLocation(s.depth_shader, "matNormal")
		s.depth_vp_loc = rl.GetShaderLocation(s.depth_shader, "viewPos")

		// Create float FBO for depth — 32-bit float per channel, no banding
		depth_fbo := rlgl.LoadFramebuffer()
		if depth_fbo != 0 {
			depth_color_id := rlgl.LoadTexture(nil, i32(c), i32(r), i32(rl.PixelFormat.UNCOMPRESSED_R32G32B32A32), 1)
			depth_depth_id := rlgl.LoadTextureDepth(i32(c), i32(r), false)
			rlgl.FramebufferAttach(depth_fbo, depth_color_id, i32(rlgl.FramebufferAttachType.COLOR_CHANNEL0), i32(rlgl.FramebufferAttachTextureType.TEXTURE2D), 0)
			rlgl.FramebufferAttach(depth_fbo, depth_depth_id, i32(rlgl.FramebufferAttachType.DEPTH), i32(rlgl.FramebufferAttachTextureType.TEXTURE2D), 0)

			if rlgl.FramebufferComplete(depth_fbo) {
				s.depth_target = rl.RenderTexture2D{
					id = depth_fbo,
					texture = rl.Texture2D{id = depth_color_id, width = i32(c), height = i32(r), mipmaps = 1, format = .UNCOMPRESSED_R32G32B32A32},
					depth = rl.Texture2D{id = depth_depth_id, width = i32(c), height = i32(r), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8},
				}
				rl.TraceLog(.INFO, "SSAO depth target created (float32, %dx%d)", i32(c), i32(r))
			} else {
				rl.TraceLog(.WARNING, "SSAO depth FBO incomplete — falling back to RGBA8")
				rlgl.UnloadFramebuffer(depth_fbo)
				rlgl.UnloadTexture(depth_color_id)
				rlgl.UnloadTexture(depth_depth_id)
				s.depth_target = rl.LoadRenderTexture(i32(c), i32(r))
			}
		} else {
			s.depth_target = rl.LoadRenderTexture(i32(c), i32(r))
		}
	}

	// SSAO post-process
	s.ssao_shader = rl.LoadShader(nil, "assets/ssao.glsl")
	if s.ssao_shader.id != 0 {
		s.ssao_res_loc = rl.GetShaderLocation(s.ssao_shader, "resolution")
		s.ssao_radius_loc = rl.GetShaderLocation(s.ssao_shader, "ssaoRadius")
		s.ssao_strength_loc = rl.GetShaderLocation(s.ssao_shader, "ssaoStrength")
		s.ssao_depth_loc = rl.GetShaderLocation(s.ssao_shader, "depthTex")
		s.ssao_target = rl.LoadRenderTexture(i32(c), i32(r))
	}

	return s
}

scene3d_destroy :: proc(s: ^Scene3D) {
	if s.enabled {
		rl.UnloadRenderTexture(s.target)
		if s.shader.id != 0 { rl.UnloadShader(s.shader) }
	}
	shadow_destroy(&s.shadow)
	if s.sky_shader.id != 0 { rl.UnloadShader(s.sky_shader) }
	if s.depth_shader.id != 0 {
		rl.UnloadShader(s.depth_shader)
		rl.UnloadRenderTexture(s.depth_target)
	}
	if s.ssao_shader.id != 0 {
		rl.UnloadShader(s.ssao_shader)
		rl.UnloadRenderTexture(s.ssao_target)
	}
}

scene3d_resize :: proc(s: ^Scene3D, cols, rows: int) {
	// Preserve lights across resize
	lights := s.lights
	count := s.light_count
	if s.enabled {
		rl.UnloadRenderTexture(s.target)
		if s.shader.id != 0 { rl.UnloadShader(s.shader) }
	}
	shadow_destroy(&s.shadow)
	if s.depth_shader.id != 0 {
		rl.UnloadShader(s.depth_shader)
		rl.UnloadRenderTexture(s.depth_target)
	}
	if s.ssao_shader.id != 0 {
		rl.UnloadShader(s.ssao_shader)
		rl.UnloadRenderTexture(s.ssao_target)
	}
	s^ = scene3d_create(cols, rows)
	// Restore lights with new shader locations already cached, copy data back
	for i in 0 ..< count {
		s.lights[i].enabled  = lights[i].enabled
		s.lights[i].type     = lights[i].type
		s.lights[i].position = lights[i].position
		s.lights[i].target   = lights[i].target
		s.lights[i].color    = lights[i].color
	}
	s.light_count = count
}

// Add a light to the scene. Returns the light index, or -1 if full.
scene3d_add_light :: proc(s: ^Scene3D, type: LightType, position, target: rl.Vector3, color: rl.Vector3) -> int {
	if s.light_count >= MAX_LIGHTS do return -1
	idx := s.light_count
	s.lights[idx].enabled  = true
	s.lights[idx].type     = type
	s.lights[idx].position = position
	s.lights[idx].target   = target
	s.lights[idx].color    = color
	s.light_count += 1
	return idx
}

// Toggle a light on/off
scene3d_toggle_light :: proc(s: ^Scene3D, idx: int) {
	if idx >= 0 && idx < s.light_count {
		s.lights[idx].enabled = !s.lights[idx].enabled
	}
}

// Upload all light uniforms to the shader
scene3d_update_lights :: proc(s: ^Scene3D) {
	for i in 0 ..< MAX_LIGHTS {
		light := &s.lights[i]
		enabled := i32(light.enabled ? 1 : 0)
		type_val := i32(light.type)
		rl.SetShaderValue(s.shader, light.enabled_loc, &enabled, .INT)
		rl.SetShaderValue(s.shader, light.type_loc, &type_val, .INT)
		rl.SetShaderValue(s.shader, light.position_loc, &light.position, .VEC3)
		rl.SetShaderValue(s.shader, light.target_loc, &light.target, .VEC3)
		rl.SetShaderValue(s.shader, light.color_loc, &light.color, .VEC3)
	}
}

// Draw all scene geometry — shared between shadow pass and color pass
// use_shader: false for shadow pass (depth only), true for color pass
// draw_fn: optional callback for custom primitives (ground, cubes, etc.)
scene3d_draw_geometry :: proc(s: ^Scene3D, models: []Scene3DObject, time: f32, use_shader: bool = true, draw_fn: proc(^Scene3D, bool) = nil) {
	// Custom draw callback (ground, primitives, etc.)
	if draw_fn != nil {
		draw_fn(s, use_shader)
	}

	// Scene objects (models)
	for &obj in models {
		if !obj.loaded do continue

		if use_shader {
			for mi in 0 ..< obj.model.materialCount {
				obj.model.materials[mi].shader = s.shader
			}

			has_nmap := i32(obj.normal_map.id != 0 ? 1 : 0)
			rl.SetShaderValue(s.shader, s.has_normal_map_loc, &has_nmap, .INT)
			if obj.normal_map.id != 0 {
				nmap_slot: i32 = 3
				rl.SetShaderValue(s.shader, s.normal_map_loc, &nmap_slot, .INT)
				rlgl.ActiveTextureSlot(nmap_slot)
				rlgl.EnableTexture(obj.normal_map.id)
			}
		}

		pos := obj.position
		rot_y := obj.rotation_y
		if obj.auto_rotate {
			rot_y += time * obj.rotate_speed
		}

		rl.DrawModelEx(
			obj.model,
			pos,
			{0, 1, 0},
			rot_y * 57.2958,
			{obj.scale, obj.scale, obj.scale},
			obj.tint,
		)

		if use_shader && obj.normal_map.id != 0 {
			rlgl.ActiveTextureSlot(3)
			rlgl.DisableTexture()
			rlgl.ActiveTextureSlot(0)
			no_nmap: i32 = 0
			rl.SetShaderValue(s.shader, s.has_normal_map_loc, &no_nmap, .INT)
		}
	}
}

// Render a full 3D scene: shadow pass → color pass
scene3d_render :: proc(
	s: ^Scene3D,
	cam: ^Camera,
	models: []Scene3DObject,
	time: f32,
	draw_fn: proc(^Scene3D, bool) = nil,
	cfg: ^Config = nil,
	particles: []RenderParticle = nil,
) {
	if !s.enabled do return

	// --- Pass 1: Shadow map from first directional light ---
	shadow_light_idx := -1
	for i in 0 ..< s.light_count {
		if s.lights[i].enabled && s.lights[i].type == .Directional {
			shadow_light_idx = i
			break
		}
	}
	has_shadow := s.shadow.enabled && shadow_light_idx >= 0

	if has_shadow {
		shadow_begin(&s.shadow, &s.lights[shadow_light_idx], {0, 0, 0}, 25)
		scene3d_draw_geometry(s, models, time, false, draw_fn) // depth only, no lighting shader
		shadow_end(&s.shadow)
	}

	// --- Pass 2: Color pass with shadow map ---
	rl.BeginTextureMode(s.target)
	rl.ClearBackground({5, 5, 12, 255})

	// Update global uniforms — use config if provided, otherwise defaults
	ambient := cfg != nil ? cfg.ambient : [3]f32{0.06, 0.06, 0.1}
	view_pos := [3]f32{cam.rl_cam.position.x, cam.rl_cam.position.y, cam.rl_cam.position.z}
	rl.SetShaderValue(s.shader, s.ambient_loc, &ambient, .VEC3)
	rl.SetShaderValue(s.shader, s.view_pos_loc, &view_pos, .VEC3)

	// Volumes — demo: blue fog zone on left side
	vol0_min := [3]f32{-20, -1, -20}
	vol0_max := [3]f32{-5, 10, 20}
	vol0_color := [3]f32{0.05, 0.08, 0.2}
	vol0_density: f32 = 0.3
	vol0_enabled: i32 = 1
	rl.SetShaderValue(s.shader, s.volume_locs[0][0], &vol0_min, .VEC3)
	rl.SetShaderValue(s.shader, s.volume_locs[0][1], &vol0_max, .VEC3)
	rl.SetShaderValue(s.shader, s.volume_locs[0][2], &vol0_color, .VEC3)
	rl.SetShaderValue(s.shader, s.volume_locs[0][3], &vol0_density, .FLOAT)
	rl.SetShaderValue(s.shader, s.volume_locs[0][4], &vol0_enabled, .INT)

	// Disable remaining volumes
	for i in 1 ..< 4 {
		disabled: i32 = 0
		rl.SetShaderValue(s.shader, s.volume_locs[i][4], &disabled, .INT)
	}

	// Fog
	fog_color := cfg != nil ? cfg.fog_color : [3]f32{0.05, 0.05, 0.08}
	fog_start := cfg != nil ? cfg.fog_start : f32(25)
	fog_end := cfg != nil ? cfg.fog_end : f32(60)
	fog_enabled: i32 = cfg != nil && cfg.fog_enabled ? 1 : (cfg == nil ? 1 : 0)
	rl.SetShaderValue(s.shader, s.fog_color_loc, &fog_color, .VEC3)
	rl.SetShaderValue(s.shader, s.fog_start_loc, &fog_start, .FLOAT)
	rl.SetShaderValue(s.shader, s.fog_end_loc, &fog_end, .FLOAT)
	rl.SetShaderValue(s.shader, s.fog_enabled_loc, &fog_enabled, .INT)

	// Upload light data
	scene3d_update_lights(s)

	// Bind shadow map
	shadow_enabled := i32(has_shadow ? 1 : 0)
	rl.SetShaderValue(s.shader, s.shadow_enabled_loc, &shadow_enabled, .INT)
	if has_shadow {
		shadow_idx := i32(shadow_light_idx)
		shadow_res := s.shadow.size
		rl.SetShaderValue(s.shader, s.shadow_light_idx_loc, &shadow_idx, .INT)
		rl.SetShaderValue(s.shader, s.shadow_map_res_loc, &shadow_res, .INT)
		shadow_bind(&s.shadow, s.shader)
	}

	rl.BeginMode3D(cam.rl_cam)

	// Sky sphere — drawn first, at camera position, no depth write
	if s.sky_shader.id != 0 {
		sky_vp := [3]f32{cam.rl_cam.position.x, cam.rl_cam.position.y, cam.rl_cam.position.z}
		rl.SetShaderValue(s.sky_shader, s.sky_vp_loc, &sky_vp, .VEC3)
		// Sun direction from the directional light
		sun_dir: [3]f32
		if shadow_light_idx >= 0 {
			l := s.lights[shadow_light_idx]
			dir := linalg.normalize(l.position - l.target)
			sun_dir = {dir.x, dir.y, dir.z}
		} else {
			sun_dir = {0.3, 0.8, 0.2} // default up-ish
		}
		rl.SetShaderValue(s.sky_shader, s.sky_sun_dir_loc, &sun_dir, .VEC3)
		rlgl.DisableBackfaceCulling() // See inside of sphere
		rlgl.DisableDepthMask()       // Don't write to depth — sky is always behind
		rl.BeginShaderMode(s.sky_shader)
		rl.DrawSphere(cam.rl_cam.position, 500, rl.WHITE)
		rl.EndShaderMode()
		rlgl.EnableDepthMask()
		rlgl.EnableBackfaceCulling()
	}

	rl.BeginShaderMode(s.shader)

	scene3d_draw_geometry(s, models, time, true, draw_fn)

	// Light indicator spheres (drawn after geometry, unaffected by shadow)
	for i in 0 ..< s.light_count {
		if !s.lights[i].enabled do continue
		if s.lights[i].type == .Point {
			r := u8(s.lights[i].color.x * 255)
			g := u8(s.lights[i].color.y * 255)
			b := u8(s.lights[i].color.z * 255)
			rl.DrawSphere(s.lights[i].position, 0.3, {r, g, b, 255})
		}
	}

	rl.EndShaderMode()

	// Draw particles (after geometry, additive blending, no lighting shader)
	if len(particles) > 0 {
		draw_particles(particles, cam)
	}

	rl.EndMode3D()
	rl.EndTextureMode()

	// Unbind shadow map
	if has_shadow {
		shadow_unbind()
	}

	// --- Depth pass (for SSAO) ---
	if s.ssao_enabled && s.depth_shader.id != 0 {
		view_pos_depth := [3]f32{cam.rl_cam.position.x, cam.rl_cam.position.y, cam.rl_cam.position.z}
		rl.SetShaderValue(s.depth_shader, s.depth_vp_loc, &view_pos_depth, .VEC3)

		rl.BeginTextureMode(s.depth_target)
		rl.ClearBackground(rl.WHITE) // Far = white (1.0)
		rl.BeginMode3D(cam.rl_cam)
		rl.BeginShaderMode(s.depth_shader)
		scene3d_draw_geometry(s, models, time, true, draw_fn)
		rl.EndShaderMode()
		rl.EndMode3D()
		rl.EndTextureMode()
	}

	// --- SSAO post-process ---
	if s.ssao_enabled && s.ssao_shader.id != 0 && s.depth_shader.id != 0 {
		res := [2]f32{f32(s.cols), f32(s.rows)}
		radius: f32 = 1.5
		strength: f32 = 8.0
		rl.SetShaderValue(s.ssao_shader, s.ssao_res_loc, &res, .VEC2)
		rl.SetShaderValue(s.ssao_shader, s.ssao_radius_loc, &radius, .FLOAT)
		rl.SetShaderValue(s.ssao_shader, s.ssao_strength_loc, &strength, .FLOAT)

		// Bind depth texture to slot 1
		depth_slot: i32 = 1
		rl.SetShaderValue(s.ssao_shader, s.ssao_depth_loc, &depth_slot, .INT)

		rl.BeginTextureMode(s.ssao_target)
		rl.ClearBackground(rl.BLACK)

		rlgl.DrawRenderBatchActive()
		rlgl.ActiveTextureSlot(depth_slot)
		rlgl.EnableTexture(s.depth_target.texture.id)
		rlgl.ActiveTextureSlot(0)

		rl.BeginShaderMode(s.ssao_shader)
		src := rl.Rectangle{0, 0, f32(s.target.texture.width), -f32(s.target.texture.height)}
		dst := rl.Rectangle{0, 0, f32(s.cols), f32(s.rows)}
		rl.DrawTexturePro(s.target.texture, src, dst, {0, 0}, 0, rl.WHITE)
		rl.EndShaderMode()

		rlgl.DrawRenderBatchActive()
		rlgl.ActiveTextureSlot(depth_slot)
		rlgl.DisableTexture()
		rlgl.ActiveTextureSlot(0)

		rl.EndTextureMode()

	}
}

// Get the final output texture — SSAO result if enabled, raw scene otherwise
scene3d_get_output :: proc(s: ^Scene3D) -> rl.Texture2D {
	if s.ssao_enabled && s.ssao_target.texture.id != 0 {
		return s.ssao_target.texture
	}
	return s.target.texture
}

// Object in a 3D scene
Scene3DObject :: struct {
	model:        rl.Model,
	loaded:       bool,
	position:     rl.Vector3,
	scale:        f32,
	rotation_y:   f32,
	auto_rotate:  bool,
	rotate_speed: f32,
	tint:         rl.Color,
	normal_map:   rl.Texture2D, // optional — set .id to 0 if none
}
