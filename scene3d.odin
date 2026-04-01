package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:fmt"

MAX_LIGHTS :: 4

// Load 6 cubemap face images into a cubemap texture.
// Expects: {prefix}_right.jpg, _left.jpg, _top.jpg, _bottom.jpg, _front.jpg, _back.jpg
// Falls back to .png if .jpg not found.
load_cubemap :: proc(prefix: string) -> rl.Texture2D {
	suffixes := [6]string{"_right", "_left", "_top", "_bottom", "_front", "_back"}
	faces: [6]rl.Image

	for i in 0 ..< 6 {
		jpg_path := strings.concatenate({prefix, suffixes[i], ".jpg"})
		png_path := strings.concatenate({prefix, suffixes[i], ".png"})
		defer delete(jpg_path)
		defer delete(png_path)

		cjpg := strings.clone_to_cstring(jpg_path)
		cpng := strings.clone_to_cstring(png_path)
		defer delete(cjpg)
		defer delete(cpng)

		faces[i] = rl.LoadImage(cjpg)
		if faces[i].data == nil {
			faces[i] = rl.LoadImage(cpng)
		}
		if faces[i].data == nil {
			// Missing face — clean up and bail
			for j in 0 ..< i {
				rl.UnloadImage(faces[j])
			}
			return {}
		}
	}

	// All 6 faces loaded — stitch into a horizontal strip (6:1 ratio) for LoadTextureCubemap
	face_size := faces[0].width
	for i in 0 ..< 6 {
		if faces[i].width != face_size || faces[i].height != face_size {
			rl.ImageResize(&faces[i], face_size, face_size)
		}
		rl.ImageFormat(&faces[i], .UNCOMPRESSED_R8G8B8A8)
	}

	strip := rl.GenImageColor(face_size * 6, face_size, rl.BLANK)
	for i in 0 ..< 6 {
		src := rl.Rectangle{0, 0, f32(face_size), f32(face_size)}
		dst := rl.Rectangle{f32(i32(i) * face_size), 0, f32(face_size), f32(face_size)}
		rl.ImageDraw(&strip, faces[i], src, dst, rl.WHITE)
	}

	cubemap := rl.LoadTextureCubemap(strip, .LINE_HORIZONTAL)
	rl.SetTextureFilter(cubemap, .BILINEAR)

	rl.UnloadImage(strip)
	for i in 0 ..< 6 {
		rl.UnloadImage(faces[i])
	}

	return cubemap
}

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
// then captures the output for the Graphon glyph shader
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
	sky_use_tex_loc:      i32,
	sky_rotation_loc:    i32,
	sky_night_loc:       i32,
	sky_model:           rl.Model,
	sky_tex:           rl.Texture2D,
	sky_night_tex:     rl.Texture2D,
	sky_cubemap:       rl.Texture2D,    // cubemap texture (GL_TEXTURE_CUBE_MAP)
	sky_night_cubemap: rl.Texture2D,
	sky_cubemap_loc:   i32,             // samplerCube uniform
	sky_use_cube_loc:  i32,
	sky_night_mode:    bool,

	// Lights
	lights:     [MAX_LIGHTS]Light,
	light_count: int,

	// Volumes (synced from Scene)
	volumes:      [4]SceneVolume,
	volume_count: int,

	// Lens flare occlusion
	flare_occlusion: FlareOcclusion,

	// Material uniform locations
	material_specular_loc:  i32,
	material_roughness_loc: i32,
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
		material_specular_loc  = rl.GetShaderLocation(shader, "materialSpecular"),
		material_roughness_loc = rl.GetShaderLocation(shader, "materialRoughness"),
		shadow                 = shadow_create(),
	}

	flare_occlusion_init(&s.flare_occlusion)

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

	// Sky shader + high-poly sphere
	s.sky_shader = rl.LoadShader("assets/lighting.vs", "assets/sky.fs")
	if s.sky_shader.id != 0 {
		s.sky_shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocation(s.sky_shader, "matModel")
		s.sky_shader.locs[rl.ShaderLocationIndex.MATRIX_NORMAL] = rl.GetShaderLocation(s.sky_shader, "matNormal")
		s.sky_vp_loc = rl.GetShaderLocation(s.sky_shader, "viewPos")
		s.sky_sun_dir_loc = rl.GetShaderLocation(s.sky_shader, "sunDirection")
		s.sky_use_tex_loc = rl.GetShaderLocation(s.sky_shader, "useTexture")
		s.sky_rotation_loc = rl.GetShaderLocation(s.sky_shader, "skyboxRotation")
		s.sky_night_loc = rl.GetShaderLocation(s.sky_shader, "nightMode")
		s.sky_cubemap_loc = rl.GetShaderLocation(s.sky_shader, "skyboxCube")
		s.sky_use_cube_loc = rl.GetShaderLocation(s.sky_shader, "useCubemap")

		sky_mesh := rl.GenMeshSphere(500, 64, 64)
		s.sky_model = rl.LoadModelFromMesh(sky_mesh)

		// Load skybox panorama if available
		sky_img := rl.LoadImage("assets/skybox.png")
		if sky_img.data == nil { sky_img = rl.LoadImage("assets/skybox.jpg") }
		if sky_img.data == nil { sky_img = rl.LoadImage("assets/skybox.hdr") }
		if sky_img.data != nil {
			// Resize to 2K if larger — saves VRAM and load time
			if sky_img.width > 2048 {
				rl.ImageResize(&sky_img, 2048, 1024)
			}
			s.sky_tex = rl.LoadTextureFromImage(sky_img)
			rl.SetTextureFilter(s.sky_tex, .BILINEAR)
			rl.SetTextureWrap(s.sky_tex, .REPEAT)
			s.sky_model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = s.sky_tex
			rl.UnloadImage(sky_img)
			rl.TraceLog(.INFO, "Skybox texture loaded")
		} else {
			rl.TraceLog(.INFO, "No skybox texture found — using procedural sky")
		}

		// Load night skybox if available
		night_img := rl.LoadImage("assets/skybox_night.jpg")
		if night_img.data == nil { night_img = rl.LoadImage("assets/skybox_night.png") }
		if night_img.data != nil {
			if night_img.width > 2048 {
				rl.ImageResize(&night_img, 2048, 1024)
			}
			s.sky_night_tex = rl.LoadTextureFromImage(night_img)
			rl.SetTextureFilter(s.sky_night_tex, .BILINEAR)
			rl.SetTextureWrap(s.sky_night_tex, .REPEAT)
			rl.UnloadImage(night_img)
			rl.TraceLog(.INFO, "Night skybox texture loaded")
		}

		// Load cubemap skybox if 6 faces exist (assets/skybox_right.jpg, etc.)
		s.sky_cubemap = load_cubemap("assets/skybox")
		if s.sky_cubemap.id != 0 {
			rl.TraceLog(.INFO, "Day cubemap skybox loaded")
		}
		s.sky_night_cubemap = load_cubemap("assets/skybox_night")
		if s.sky_night_cubemap.id != 0 {
			rl.TraceLog(.INFO, "Night cubemap skybox loaded")
		}
	}

	return s
}

scene3d_destroy :: proc(s: ^Scene3D) {
	if s.enabled {
		rl.UnloadRenderTexture(s.target)
		if s.shader.id != 0 { rl.UnloadShader(s.shader) }
	}
	shadow_destroy(&s.shadow)
	flare_occlusion_destroy(&s.flare_occlusion)
	if s.sky_shader.id != 0 {
		if s.sky_tex.id != 0 { rl.UnloadTexture(s.sky_tex) }
		if s.sky_night_tex.id != 0 { rl.UnloadTexture(s.sky_night_tex) }
		if s.sky_cubemap.id != 0 { rl.UnloadTexture(s.sky_cubemap) }
		if s.sky_night_cubemap.id != 0 { rl.UnloadTexture(s.sky_night_cubemap) }
		rl.UnloadModel(s.sky_model)
		rl.UnloadShader(s.sky_shader)
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
scene3d_draw_geometry :: proc(s: ^Scene3D, models: []Scene3DObject, time: f32, use_shader: bool = true, draw_fn: proc(^Scene3D, bool) = nil, cam: ^Camera = nil) {
	// Default material for primitives drawn via callback
	if use_shader {
		default_spec: f32 = 0.3
		default_rough: f32 = 0.5
		rl.SetShaderValue(s.shader, s.material_specular_loc, &default_spec, .FLOAT)
		rl.SetShaderValue(s.shader, s.material_roughness_loc, &default_rough, .FLOAT)
	}

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

			// Per-object material
			spec := obj.specular
			rough := obj.roughness
			rl.SetShaderValue(s.shader, s.material_specular_loc, &spec, .FLOAT)
			rl.SetShaderValue(s.shader, s.material_roughness_loc, &rough, .FLOAT)

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

		if obj.billboard && cam != nil {
			// Look-at camera POSITION — plane normal (Y+) points at camera
			dir := linalg.normalize(rl.Vector3{
				cam.rl_cam.position.x - pos.x,
				cam.rl_cam.position.y - pos.y,
				cam.rl_cam.position.z - pos.z,
			})

			// Flip — plane face should point AT camera, not away
			dir = -dir

			// Build orthonormal basis: Y→dir, X→right, Z→up
			world_up := rl.Vector3{0, 1, 0}
			right: rl.Vector3
			if math.abs(dir.y) > 0.999 {
				right = {1, 0, 0}
			} else {
				right = linalg.normalize(linalg.cross(world_up, dir))
			}
			up := linalg.cross(dir, right)

			// Columns: X=right, Y=dir(normal), Z=up
			obj.model.transform = rl.Matrix{
				right.x, dir.x, up.x, 0,
				right.y, dir.y, up.y, 0,
				right.z, dir.z, up.z, 0,
				0,       0,     0,    1,
			}
			rot_y = 0
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
		shadow_radius := cfg != nil ? cfg.shadow_radius : f32(15)
		shadow_begin(&s.shadow, &s.lights[shadow_light_idx], {0, 0, 0}, shadow_radius)
		scene3d_draw_geometry(s, models, time, false, draw_fn, cam) // depth only, no lighting shader
		shadow_end(&s.shadow)
	}

	// --- Pass 2: Color pass with shadow map ---
	rl.BeginTextureMode(s.target)
	rl.ClearBackground({5, 5, 12, 255})

	// Update global uniforms — use config if provided, otherwise defaults
	ambient := cfg != nil ? cfg.ambient : [3]f32{0.06, 0.06, 0.1}
	// Night mode: dim ambient to moonlight levels
	if s.sky_night_mode {
		ambient = {0.01, 0.01, 0.03}
	}
	view_pos := [3]f32{cam.rl_cam.position.x, cam.rl_cam.position.y, cam.rl_cam.position.z}
	rl.SetShaderValue(s.shader, s.ambient_loc, &ambient, .VEC3)
	rl.SetShaderValue(s.shader, s.view_pos_loc, &view_pos, .VEC3)

	// Upload volumes from scene data
	for i in 0 ..< 4 {
		if i < s.volume_count && s.volumes[i].enabled {
			min_p := [3]f32{s.volumes[i].min_pos.x, s.volumes[i].min_pos.y, s.volumes[i].min_pos.z}
			max_p := [3]f32{s.volumes[i].max_pos.x, s.volumes[i].max_pos.y, s.volumes[i].max_pos.z}
			col := [3]f32{s.volumes[i].color.x, s.volumes[i].color.y, s.volumes[i].color.z}
			dens := s.volumes[i].density
			en: i32 = 1
			rl.SetShaderValue(s.shader, s.volume_locs[i][0], &min_p, .VEC3)
			rl.SetShaderValue(s.shader, s.volume_locs[i][1], &max_p, .VEC3)
			rl.SetShaderValue(s.shader, s.volume_locs[i][2], &col, .VEC3)
			rl.SetShaderValue(s.shader, s.volume_locs[i][3], &dens, .FLOAT)
			rl.SetShaderValue(s.shader, s.volume_locs[i][4], &en, .INT)
		} else {
			disabled: i32 = 0
			rl.SetShaderValue(s.shader, s.volume_locs[i][4], &disabled, .INT)
		}
	}

	// Fog — dark at night
	fog_color := cfg != nil ? cfg.fog_color : [3]f32{0.05, 0.05, 0.08}
	if s.sky_night_mode { fog_color = {0.02, 0.02, 0.04} }
	fog_start := cfg != nil ? cfg.fog_start : f32(25)
	fog_end := cfg != nil ? cfg.fog_end : f32(60)
	fog_enabled: i32 = cfg != nil && cfg.fog_enabled ? 1 : (cfg == nil ? 1 : 0)
	rl.SetShaderValue(s.shader, s.fog_color_loc, &fog_color, .VEC3)
	rl.SetShaderValue(s.shader, s.fog_start_loc, &fog_start, .FLOAT)
	rl.SetShaderValue(s.shader, s.fog_end_loc, &fog_end, .FLOAT)
	rl.SetShaderValue(s.shader, s.fog_enabled_loc, &fog_enabled, .INT)

	// Upload light data — dim for night mode
	if s.sky_night_mode {
		// Temporarily scale light colors to moonlight levels
		saved_colors: [MAX_LIGHTS]rl.Vector3
		for i in 0 ..< s.light_count {
			saved_colors[i] = s.lights[i].color
			s.lights[i].color = {
				s.lights[i].color.x * 0.08,
				s.lights[i].color.y * 0.08,
				s.lights[i].color.z * 0.12, // slightly blue moonlight
			}
		}
		scene3d_update_lights(s)
		// Restore original colors
		for i in 0 ..< s.light_count {
			s.lights[i].color = saved_colors[i]
		}
	} else {
		scene3d_update_lights(s)
	}

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
		// Swap sky texture for night mode
		active_tex := s.sky_night_mode && s.sky_night_tex.id != 0 ? s.sky_night_tex : s.sky_tex
		if active_tex.id != 0 {
			s.sky_model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = active_tex
		}
		use_tex := i32(active_tex.id != 0 ? 1 : 0)
		rl.SetShaderValue(s.sky_shader, s.sky_use_tex_loc, &use_tex, .INT)

		// Night mode flag for shader (moon instead of sun)
		night_val := i32(s.sky_night_mode ? 1 : 0)
		rl.SetShaderValue(s.sky_shader, s.sky_night_loc, &night_val, .INT)

		// Cubemap support — bind if available
		active_cube := s.sky_night_mode && s.sky_night_cubemap.id != 0 ? s.sky_night_cubemap : s.sky_cubemap
		use_cube := i32(active_cube.id != 0 ? 1 : 0)
		rl.SetShaderValue(s.sky_shader, s.sky_use_cube_loc, &use_cube, .INT)
		if active_cube.id != 0 {
			cube_slot: i32 = 3
			rl.SetShaderValue(s.sky_shader, s.sky_cubemap_loc, &cube_slot, .INT)
			rlgl.ActiveTextureSlot(cube_slot)
			rlgl.EnableTextureCubemap(active_cube.id)
		}

		rlgl.DisableBackfaceCulling()
		rlgl.DisableDepthMask()
		rlgl.DisableDepthTest()
		rlgl.DisableColorBlend()  // write sky directly — alpha=0 marks it for bloom exclusion
		s.sky_model.materials[0].shader = s.sky_shader
		rl.DrawModel(s.sky_model, cam.rl_cam.position, 1.0, rl.WHITE)
		rlgl.DrawRenderBatchActive()  // flush before re-enabling blend
		rlgl.EnableColorBlend()

		if active_cube.id != 0 {
			rlgl.ActiveTextureSlot(3)
			rlgl.DisableTextureCubemap()
			rlgl.ActiveTextureSlot(0)
		}

		rlgl.EnableDepthTest()
		rlgl.EnableDepthMask()
		rlgl.EnableBackfaceCulling()
	}

	rl.BeginShaderMode(s.shader)

	scene3d_draw_geometry(s, models, time, true, draw_fn, cam)

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

	// Lens flare occlusion — read depth at sun's screen position
	if s.flare_occlusion.initialized {
		for i in 0 ..< s.light_count {
			if !s.lights[i].enabled do continue
			if s.lights[i].type != .Directional do continue
			light_dir := linalg.normalize(s.lights[i].position - s.lights[i].target)
			view_dir := linalg.normalize(cam.rl_cam.target - cam.rl_cam.position)
			// Only read depth when sun is in front of camera
			if linalg.dot(light_dir, view_dir) > 0 {
				far_point := cam.rl_cam.position + light_dir * 200
				sun_screen := rl.GetWorldToScreen(far_point, cam.rl_cam)
				flare_occlusion_update(&s.flare_occlusion, sun_screen)
			} else {
				// Sun behind camera — fade out
				speed := f32(20.0) * rl.GetFrameTime()
				s.flare_occlusion.occlusion += (0 - s.flare_occlusion.occlusion) * clamp(speed, 0, 1)
			}
			break
		}
	}

	rl.EndMode3D()

	// Lens flares — 2D screen-space, drawn after EndMode3D
	draw_lens_flares(s, cam)

	rl.EndTextureMode()

	// Unbind shadow map
	if has_shadow {
		shadow_unbind()
	}

}

// Get the final output texture
scene3d_get_output :: proc(s: ^Scene3D) -> rl.Texture2D {
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
	specular:     f32,
	roughness:    f32,
	billboard:    bool, // always face camera
}
