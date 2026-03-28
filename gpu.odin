package main

import rl "vendor:raylib"

// Post-process effect types
PostFX :: enum {
	None,
	Bloom,
	Scanlines,
	Chromatic,
}

POST_FX_COUNT :: 4

// GPU rendering pipeline: render to texture, apply post-process shaders
GPUPipeline :: struct {
	target:           rl.RenderTexture2D,
	bloom_shader:     rl.Shader,
	scanline_shader:  rl.Shader,
	chromatic_shader: rl.Shader,
	active_fx:        PostFX,

	// Shader uniform locations
	bloom_resolution_loc:  i32,
	bloom_intensity_loc:   i32,
	bloom_threshold_loc:   i32,
	scan_resolution_loc:   i32,
	scan_intensity_loc:    i32,
	scan_time_loc:         i32,
	chrom_resolution_loc:  i32,
	chrom_amount_loc:      i32,

	// Parameters
	bloom_intensity:    f32,
	bloom_threshold:    f32,
	scanline_intensity: f32,
	aberration_amount:  f32,
}

gpu_create :: proc(screen_w, screen_h: i32) -> GPUPipeline {
	gpu := GPUPipeline{
		bloom_intensity    = 0.4,
		bloom_threshold    = 0.5,
		scanline_intensity = 0.3,
		aberration_amount  = 2.0,
		active_fx          = .None,
	}

	gpu.target = rl.LoadRenderTexture(screen_w, screen_h)

	// Load shaders (nil vertex = default vertex shader)
	gpu.bloom_shader = rl.LoadShader(nil, "assets/bloom.glsl")
	gpu.scanline_shader = rl.LoadShader(nil, "assets/scanlines.glsl")
	gpu.chromatic_shader = rl.LoadShader(nil, "assets/chromatic.glsl")

	// Get uniform locations
	gpu.bloom_resolution_loc = rl.GetShaderLocation(gpu.bloom_shader, "resolution")
	gpu.bloom_intensity_loc = rl.GetShaderLocation(gpu.bloom_shader, "bloomIntensity")
	gpu.bloom_threshold_loc = rl.GetShaderLocation(gpu.bloom_shader, "bloomThreshold")

	gpu.scan_resolution_loc = rl.GetShaderLocation(gpu.scanline_shader, "resolution")
	gpu.scan_intensity_loc = rl.GetShaderLocation(gpu.scanline_shader, "scanlineIntensity")
	gpu.scan_time_loc = rl.GetShaderLocation(gpu.scanline_shader, "time")

	gpu.chrom_resolution_loc = rl.GetShaderLocation(gpu.chromatic_shader, "resolution")
	gpu.chrom_amount_loc = rl.GetShaderLocation(gpu.chromatic_shader, "aberrationAmount")

	// Set resolution
	res := [2]f32{f32(screen_w), f32(screen_h)}
	rl.SetShaderValue(gpu.bloom_shader, gpu.bloom_resolution_loc, &res, .VEC2)
	rl.SetShaderValue(gpu.scanline_shader, gpu.scan_resolution_loc, &res, .VEC2)
	rl.SetShaderValue(gpu.chromatic_shader, gpu.chrom_resolution_loc, &res, .VEC2)

	return gpu
}

gpu_destroy :: proc(gpu: ^GPUPipeline) {
	rl.UnloadRenderTexture(gpu.target)
	rl.UnloadShader(gpu.bloom_shader)
	rl.UnloadShader(gpu.scanline_shader)
	rl.UnloadShader(gpu.chromatic_shader)
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

// Draw the offscreen texture to screen with active post-process effect
gpu_present :: proc(gpu: ^GPUPipeline, time_val: f32) {
	time := time_val
	// Update shader uniforms
	switch gpu.active_fx {
	case .Bloom:
		rl.SetShaderValue(gpu.bloom_shader, gpu.bloom_intensity_loc, &gpu.bloom_intensity, .FLOAT)
		rl.SetShaderValue(gpu.bloom_shader, gpu.bloom_threshold_loc, &gpu.bloom_threshold, .FLOAT)
	case .Scanlines:
		rl.SetShaderValue(gpu.scanline_shader, gpu.scan_intensity_loc, &gpu.scanline_intensity, .FLOAT)
		rl.SetShaderValue(gpu.scanline_shader, gpu.scan_time_loc, &time, .FLOAT)
	case .Chromatic:
		rl.SetShaderValue(gpu.chromatic_shader, gpu.chrom_amount_loc, &gpu.aberration_amount, .FLOAT)
	case .None:
	}

	// Get active shader
	shader: rl.Shader
	use_shader := true
	switch gpu.active_fx {
	case .Bloom:     shader = gpu.bloom_shader
	case .Scanlines: shader = gpu.scanline_shader
	case .Chromatic: shader = gpu.chromatic_shader
	case .None:      use_shader = false
	}

	// Draw render texture flipped (RenderTexture is upside down in OpenGL)
	src := rl.Rectangle{0, 0, f32(gpu.target.texture.width), -f32(gpu.target.texture.height)}
	dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	if use_shader { rl.BeginShaderMode(shader) }
	rl.DrawTexturePro(gpu.target.texture, src, dst, {0, 0}, 0, rl.WHITE)
	if use_shader { rl.EndShaderMode() }
}

// Cycle to next post-process effect
gpu_cycle_fx :: proc(gpu: ^GPUPipeline) {
	gpu.active_fx = PostFX((int(gpu.active_fx) + 1) % POST_FX_COUNT)
}
