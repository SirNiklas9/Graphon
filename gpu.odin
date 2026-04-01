package main

import rl "vendor:raylib"

// Post-process effects — can be combined
PostFX :: bit_set[PostFXFlag]

PostFXFlag :: enum {
	Bloom,
	Scanlines,
	Chromatic,
}

BLOOM_MIP_COUNT :: 3 // number of downsample levels

// GPU rendering pipeline: render to texture, apply post-process shader
GPUPipeline :: struct {
	target:  rl.RenderTexture2D,
	shader:  rl.Shader,

	// Bloom multi-pass
	bloom_down_shader: rl.Shader,
	bloom_up_shader:   rl.Shader,
	bloom_mips:        [BLOOM_MIP_COUNT]rl.RenderTexture2D,

	// Uniform locations — postfx
	resolution_loc:       i32,
	time_loc:             i32,
	enable_bloom_loc:     i32,
	enable_scanlines_loc: i32,
	enable_chromatic_loc: i32,
	bloom_intensity_loc:  i32,
	bloom_threshold_loc:  i32,
	scanline_intensity_loc: i32,
	aberration_amount_loc:  i32,

	// Uniform locations — bloom shaders
	bloom_down_res_loc:       i32,
	bloom_down_threshold_loc: i32,
	bloom_down_first_loc:     i32,
	bloom_up_res_loc:         i32,

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

	// Bloom shaders
	gpu.bloom_down_shader = rl.LoadShader(nil, "assets/bloom_down.glsl")
	gpu.bloom_up_shader = rl.LoadShader(nil, "assets/bloom_up.glsl")
	gpu.bloom_down_res_loc = rl.GetShaderLocation(gpu.bloom_down_shader, "resolution")
	gpu.bloom_down_threshold_loc = rl.GetShaderLocation(gpu.bloom_down_shader, "bloomThreshold")
	gpu.bloom_down_first_loc = rl.GetShaderLocation(gpu.bloom_down_shader, "firstPass")
	gpu.bloom_up_res_loc = rl.GetShaderLocation(gpu.bloom_up_shader, "resolution")

	// Create bloom mip chain (each half the size of the previous)
	mip_w := screen_w / 2
	mip_h := screen_h / 2
	for i in 0 ..< BLOOM_MIP_COUNT {
		gpu.bloom_mips[i] = rl.LoadRenderTexture(mip_w, mip_h)
		rl.SetTextureFilter(gpu.bloom_mips[i].texture, .BILINEAR)
		mip_w = max(mip_w / 2, 1)
		mip_h = max(mip_h / 2, 1)
	}

	return gpu
}

gpu_destroy :: proc(gpu: ^GPUPipeline) {
	rl.UnloadRenderTexture(gpu.target)
	rl.UnloadShader(gpu.shader)
	rl.UnloadShader(gpu.bloom_down_shader)
	rl.UnloadShader(gpu.bloom_up_shader)
	for i in 0 ..< BLOOM_MIP_COUNT {
		rl.UnloadRenderTexture(gpu.bloom_mips[i])
	}
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

// Run multi-pass bloom: downsample with bright extraction, then upsample+blend
gpu_bloom_pass :: proc(gpu: ^GPUPipeline) {
	// --- Downsample chain ---
	for i in 0 ..< BLOOM_MIP_COUNT {
		mip := &gpu.bloom_mips[i]
		mip_w := f32(mip.texture.width)
		mip_h := f32(mip.texture.height)
		res := [2]f32{mip_w, mip_h}

		rl.SetShaderValue(gpu.bloom_down_shader, gpu.bloom_down_res_loc, &res, .VEC2)
		rl.SetShaderValue(gpu.bloom_down_shader, gpu.bloom_down_threshold_loc, &gpu.bloom_threshold, .FLOAT)
		first: i32 = i == 0 ? 1 : 0
		rl.SetShaderValue(gpu.bloom_down_shader, gpu.bloom_down_first_loc, &first, .INT)

		// Source: previous level (or original scene for first pass)
		src_tex: rl.Texture2D
		if i == 0 {
			src_tex = gpu.target.texture
		} else {
			src_tex = gpu.bloom_mips[i - 1].texture
		}

		rl.BeginTextureMode(mip^)
		rl.ClearBackground(rl.BLACK)
		rl.BeginShaderMode(gpu.bloom_down_shader)
		src := rl.Rectangle{0, 0, f32(src_tex.width), -f32(src_tex.height)}
		dst := rl.Rectangle{0, 0, mip_w, mip_h}
		rl.DrawTexturePro(src_tex, src, dst, {0, 0}, 0, rl.WHITE)
		rl.EndShaderMode()
		rl.EndTextureMode()
	}

	// --- Upsample chain (blend back up, accumulating into each level) ---
	for i := BLOOM_MIP_COUNT - 1; i > 0; i -= 1 {
		src_mip := &gpu.bloom_mips[i]
		dst_mip := &gpu.bloom_mips[i - 1]
		dst_w := f32(dst_mip.texture.width)
		dst_h := f32(dst_mip.texture.height)

		// Resolution of the source (smaller) texture for the tent filter
		src_res := [2]f32{f32(src_mip.texture.width), f32(src_mip.texture.height)}
		rl.SetShaderValue(gpu.bloom_up_shader, gpu.bloom_up_res_loc, &src_res, .VEC2)

		rl.BeginTextureMode(dst_mip^)
		// Don't clear — we ADD the upsampled result to what's already there
		rl.BeginBlendMode(.ADDITIVE)
		rl.BeginShaderMode(gpu.bloom_up_shader)
		src := rl.Rectangle{0, 0, f32(src_mip.texture.width), -f32(src_mip.texture.height)}
		dst := rl.Rectangle{0, 0, dst_w, dst_h}
		rl.DrawTexturePro(src_mip.texture, src, dst, {0, 0}, 0, rl.WHITE)
		rl.EndShaderMode()
		rl.EndBlendMode()
		rl.EndTextureMode()
	}
}

// Draw the offscreen texture to screen with active post-process effects
gpu_present :: proc(gpu: ^GPUPipeline, time_val: f32) {
	time := time_val

	// Run multi-pass bloom if enabled
	if .Bloom in gpu.active_fx {
		gpu_bloom_pass(gpu)
	}

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

	// Bind bloom texture to slot 1 for the postfx shader
	if .Bloom in gpu.active_fx {
		bloom_slot: i32 = 1
		bloom_tex_loc := rl.GetShaderLocation(gpu.shader, "bloomTex")
		rl.SetShaderValue(gpu.shader, bloom_tex_loc, &bloom_slot, .INT)
		rl.SetTextureFilter(gpu.bloom_mips[0].texture, .BILINEAR)
	}

	src := rl.Rectangle{0, 0, f32(gpu.target.texture.width), -f32(gpu.target.texture.height)}
	dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	rl.BeginShaderMode(gpu.shader)

	// Bind bloom result to texture slot 1
	if .Bloom in gpu.active_fx {
		rl.SetShaderValueTexture(gpu.shader, rl.GetShaderLocation(gpu.shader, "bloomTex"), gpu.bloom_mips[0].texture)
	}

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
