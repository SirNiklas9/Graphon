package main

import rl "vendor:raylib"

// Post-process effects — can be combined
PostFX :: bit_set[PostFXFlag]

PostFXFlag :: enum {
	Bloom,
	Scanlines,
	Chromatic,
}

// GPU rendering pipeline: render to texture, apply post-process shader
GPUPipeline :: struct {
	target:  rl.RenderTexture2D,
	shader:  rl.Shader,

	// Uniform locations
	resolution_loc:       i32,
	time_loc:             i32,
	enable_bloom_loc:     i32,
	enable_scanlines_loc: i32,
	enable_chromatic_loc: i32,
	bloom_intensity_loc:  i32,
	bloom_threshold_loc:  i32,
	scanline_intensity_loc: i32,
	aberration_amount_loc:  i32,

	// Parameters
	bloom_intensity:    f32,
	bloom_threshold:    f32,
	scanline_intensity: f32,
	aberration_amount:  f32,

	// Active effects
	active_fx: PostFX,
}

gpu_create :: proc(screen_w, screen_h: i32) -> GPUPipeline {
	gpu := GPUPipeline{
		bloom_intensity    = 0.25,
		bloom_threshold    = 0.75,
		scanline_intensity = 0.3,
		aberration_amount  = 2.0,
		active_fx          = {},
	}

	gpu.target = rl.LoadRenderTexture(screen_w, screen_h)
	gpu.shader = rl.LoadShader(nil, "assets/postfx.glsl")

	gpu.resolution_loc = rl.GetShaderLocation(gpu.shader, "resolution")
	gpu.time_loc = rl.GetShaderLocation(gpu.shader, "time")
	gpu.enable_bloom_loc = rl.GetShaderLocation(gpu.shader, "enableBloom")
	gpu.enable_scanlines_loc = rl.GetShaderLocation(gpu.shader, "enableScanlines")
	gpu.enable_chromatic_loc = rl.GetShaderLocation(gpu.shader, "enableChromatic")
	gpu.bloom_intensity_loc = rl.GetShaderLocation(gpu.shader, "bloomIntensity")
	gpu.bloom_threshold_loc = rl.GetShaderLocation(gpu.shader, "bloomThreshold")
	gpu.scanline_intensity_loc = rl.GetShaderLocation(gpu.shader, "scanlineIntensity")
	gpu.aberration_amount_loc = rl.GetShaderLocation(gpu.shader, "aberrationAmount")

	res := [2]f32{f32(screen_w), f32(screen_h)}
	rl.SetShaderValue(gpu.shader, gpu.resolution_loc, &res, .VEC2)

	return gpu
}

gpu_destroy :: proc(gpu: ^GPUPipeline) {
	rl.UnloadRenderTexture(gpu.target)
	rl.UnloadShader(gpu.shader)
}

// Begin rendering to the offscreen texture
gpu_begin :: proc(gpu: ^GPUPipeline) {
	rl.BeginTextureMode(gpu.target)
	rl.ClearBackground(rl.BLACK)
}

// End offscreen rendering
gpu_end :: proc(gpu: ^GPUPipeline) {
	rl.EndTextureMode()
}

// Draw the offscreen texture to screen with active post-process effects
gpu_present :: proc(gpu: ^GPUPipeline, time_val: f32) {
	time := time_val

	// Upload all uniforms
	bloom_on: i32 = .Bloom in gpu.active_fx ? 1 : 0
	scan_on: i32 = .Scanlines in gpu.active_fx ? 1 : 0
	chrom_on: i32 = .Chromatic in gpu.active_fx ? 1 : 0

	rl.SetShaderValue(gpu.shader, gpu.enable_bloom_loc, &bloom_on, .INT)
	rl.SetShaderValue(gpu.shader, gpu.enable_scanlines_loc, &scan_on, .INT)
	rl.SetShaderValue(gpu.shader, gpu.enable_chromatic_loc, &chrom_on, .INT)
	rl.SetShaderValue(gpu.shader, gpu.time_loc, &time, .FLOAT)
	rl.SetShaderValue(gpu.shader, gpu.bloom_intensity_loc, &gpu.bloom_intensity, .FLOAT)
	rl.SetShaderValue(gpu.shader, gpu.bloom_threshold_loc, &gpu.bloom_threshold, .FLOAT)
	rl.SetShaderValue(gpu.shader, gpu.scanline_intensity_loc, &gpu.scanline_intensity, .FLOAT)
	rl.SetShaderValue(gpu.shader, gpu.aberration_amount_loc, &gpu.aberration_amount, .FLOAT)

	src := rl.Rectangle{0, 0, f32(gpu.target.texture.width), -f32(gpu.target.texture.height)}
	dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	rl.BeginShaderMode(gpu.shader)
	rl.DrawTexturePro(gpu.target.texture, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()
}

// Toggle a specific effect on/off
gpu_toggle_fx :: proc(gpu: ^GPUPipeline, fx: PostFXFlag) {
	if fx in gpu.active_fx {
		gpu.active_fx -= {fx}
	} else {
		gpu.active_fx += {fx}
	}
}

// Check if any effect is active
gpu_has_fx :: proc(gpu: ^GPUPipeline) -> bool {
	return gpu.active_fx != {}
}
