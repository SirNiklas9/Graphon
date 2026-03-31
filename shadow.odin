package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"
import "core:math/linalg"

SHADOW_MAP_SIZE :: 4096

ShadowMap :: struct {
	id:        u32,          // framebuffer ID
	depth_tex: rl.Texture2D, // depth texture (sampled in lighting shader)
	size:      i32,
	enabled:   bool,
	light_vp:  rl.Matrix,    // light view-projection matrix (uploaded to shader)
}

shadow_create :: proc(size: i32 = SHADOW_MAP_SIZE) -> ShadowMap {
	sm := ShadowMap{
		size    = size,
		enabled = false,
	}

	sm.id = rlgl.LoadFramebuffer()
	if sm.id == 0 {
		rl.TraceLog(.WARNING, "Shadow map framebuffer failed to create")
		return sm
	}

	depth_id := rlgl.LoadTextureDepth(size, size, false)
	if depth_id == 0 {
		rl.TraceLog(.WARNING, "Shadow map depth texture failed to create")
		rlgl.UnloadFramebuffer(sm.id)
		sm.id = 0
		return sm
	}

	sm.depth_tex = rl.Texture2D{
		id      = depth_id,
		width   = size,
		height  = size,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}

	// NEAREST filtering — no depth interpolation at shadow edges
	rlgl.TextureParameters(depth_id, rlgl.TEXTURE_MIN_FILTER, rlgl.TEXTURE_FILTER_NEAREST)
	rlgl.TextureParameters(depth_id, rlgl.TEXTURE_MAG_FILTER, rlgl.TEXTURE_FILTER_NEAREST)
	// Clamp to edge — prevents sampling outside shadow map
	rlgl.TextureParameters(depth_id, rlgl.TEXTURE_WRAP_S, rlgl.TEXTURE_WRAP_CLAMP)
	rlgl.TextureParameters(depth_id, rlgl.TEXTURE_WRAP_T, rlgl.TEXTURE_WRAP_CLAMP)

	// Attach depth texture to framebuffer
	rlgl.FramebufferAttach(sm.id, depth_id, i32(rlgl.FramebufferAttachType.DEPTH), i32(rlgl.FramebufferAttachTextureType.TEXTURE2D), 0)

	if rlgl.FramebufferComplete(sm.id) {
		sm.enabled = true
		rl.TraceLog(.INFO, "Shadow map created (%dx%d)", size, size)
	} else {
		rl.TraceLog(.WARNING, "Shadow map framebuffer incomplete")
		rlgl.UnloadFramebuffer(sm.id)
		rlgl.UnloadTexture(depth_id)
		sm.id = 0
	}

	return sm
}

shadow_destroy :: proc(sm: ^ShadowMap) {
	if sm.id != 0 {
		rlgl.UnloadFramebuffer(sm.id)
	}
	if sm.depth_tex.id != 0 {
		rlgl.UnloadTexture(sm.depth_tex.id)
	}
}

// Render the scene from the light's perspective into the depth buffer
shadow_begin :: proc(sm: ^ShadowMap, light: ^Light, scene_center: rl.Vector3 = {0, 0, 0}, scene_radius: f32 = 20) {
	if !sm.enabled do return

	// Compute light direction and camera position
	light_dir: rl.Vector3
	if light.type == .Directional {
		light_dir = linalg.normalize(light.target - light.position)
	} else {
		light_dir = linalg.normalize(scene_center - light.position)
	}

	light_pos := scene_center - light_dir * scene_radius

	// Set up the light's orthographic camera
	light_cam := rl.Camera3D{
		position   = light_pos,
		target     = scene_center,
		up         = {0, 1, 0},
		fovy       = scene_radius * 2, // ortho uses fovy as height
		projection = .ORTHOGRAPHIC,
	}

	// Bind shadow framebuffer and set viewport
	rlgl.DrawRenderBatchActive()
	rlgl.EnableFramebuffer(sm.id)
	rlgl.ClearColor(255, 255, 255, 255)
	rlgl.ClearScreenBuffers()
	rlgl.Viewport(0, 0, sm.size, sm.size)

	// Cull FRONT faces — render back faces only into shadow map
	// Prevents self-shadowing moiré on objects
	rlgl.SetCullFace(.FRONT)

	// Begin 3D mode with the light camera
	rl.BeginMode3D(light_cam)

	// Raylib's ortho uses window aspect — override with 1:1 for square shadow map
	// and proper near/far for the scene
	light_view := rlgl.GetMatrixModelview()

	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.LoadIdentity()
	r := f64(scene_radius)
	rlgl.Ortho(-r, r, -r, r, f64(0.1), r * 4)
	rlgl.MatrixMode(rlgl.MODELVIEW)

	light_proj := rlgl.GetMatrixProjection()
	sm.light_vp = linalg.matrix_mul(light_proj, light_view)
}

shadow_end :: proc(sm: ^ShadowMap) {
	if !sm.enabled do return

	rl.EndMode3D()

	// Restore normal back-face culling
	rlgl.SetCullFace(.BACK)

	rlgl.DrawRenderBatchActive()
	rlgl.DisableFramebuffer()

	// Restore viewport
	rlgl.Viewport(0, 0, i32(rl.GetScreenWidth()), i32(rl.GetScreenHeight()))
}

// Bind shadow map to a shader for sampling
shadow_bind :: proc(sm: ^ShadowMap, shader: rl.Shader, slot: i32 = 10) {
	if !sm.enabled do return

	shadow_map_loc := rl.GetShaderLocation(shader, "shadowMap")
	light_vp_loc := rl.GetShaderLocation(shader, "lightVP")

	// Upload light VP matrix
	rl.SetShaderValueMatrix(shader, light_vp_loc, sm.light_vp)

	// Bind depth texture to slot
	rlgl.DrawRenderBatchActive()
	rlgl.ActiveTextureSlot(slot)
	rlgl.EnableTexture(sm.depth_tex.id)

	slot_val := slot
	rl.SetShaderValue(shader, shadow_map_loc, &slot_val, .INT)
}

// Unbind shadow map after rendering
shadow_unbind :: proc(slot: i32 = 10) {
	rlgl.DrawRenderBatchActive()
	rlgl.ActiveTextureSlot(slot)
	rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(0)
}
