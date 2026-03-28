package main

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

// Light types
LightType :: enum {
	Directional,
	Point,
}

Light :: struct {
	type:      LightType,
	position:  rl.Vector3, // point light position
	direction: rl.Vector3, // directional light direction (normalized)
	color:     [4]u8,
	intensity: f32,        // 0.0–1.0+
	radius:    f32,        // point light falloff radius
}

// Scene lighting state
Lighting :: struct {
	lights:  [dynamic]Light,
	ambient: [4]u8,
}

lighting_create :: proc(ambient: [4]u8 = {30, 30, 30, 255}) -> Lighting {
	return Lighting{
		lights  = make([dynamic]Light),
		ambient = ambient,
	}
}

lighting_destroy :: proc(l: ^Lighting) {
	delete(l.lights)
}

add_directional :: proc(l: ^Lighting, direction: rl.Vector3, color: [4]u8, intensity: f32 = 1.0) {
	append(&l.lights, Light{
		type      = .Directional,
		direction = linalg.normalize(direction),
		color     = color,
		intensity = intensity,
	})
}

add_point_light :: proc(l: ^Lighting, position: rl.Vector3, color: [4]u8, intensity: f32 = 1.0, radius: f32 = 15.0) {
	append(&l.lights, Light{
		type      = .Point,
		position  = position,
		color     = color,
		intensity = intensity,
		radius    = radius,
	})
}

// Calculate lighting for a surface point with a normal
// Returns the lit color
light_point :: proc(l: ^Lighting, surface_color: [4]u8, point: rl.Vector3, normal: rl.Vector3) -> [4]u8 {
	// Start with ambient
	r: f32 = f32(l.ambient[0]) / 255.0
	g: f32 = f32(l.ambient[1]) / 255.0
	b: f32 = f32(l.ambient[2]) / 255.0

	norm := linalg.normalize(normal)

	for &light in l.lights {
		switch light.type {
		case .Directional:
			// Dot product of normal and light direction (negate because direction points FROM light)
			ndotl := max(linalg.dot(norm, -light.direction), 0.0)
			contrib := ndotl * light.intensity
			r += f32(light.color[0]) / 255.0 * contrib
			g += f32(light.color[1]) / 255.0 * contrib
			b += f32(light.color[2]) / 255.0 * contrib

		case .Point:
			to_light := light.position - point
			dist := linalg.length(to_light)
			if dist > light.radius do continue

			dir := to_light / dist
			ndotl := max(linalg.dot(norm, dir), 0.0)

			// Attenuation: linear falloff
			attenuation := 1.0 - (dist / light.radius)
			contrib := ndotl * light.intensity * attenuation
			r += f32(light.color[0]) / 255.0 * contrib
			g += f32(light.color[1]) / 255.0 * contrib
			b += f32(light.color[2]) / 255.0 * contrib
		}
	}

	// Clamp total light contribution
	r = min(r, 1.5)
	g = min(g, 1.5)
	b = min(b, 1.5)

	// Apply lighting to surface color
	return {
		u8(clamp(f32(surface_color[0]) * r, 0, 255)),
		u8(clamp(f32(surface_color[1]) * g, 0, 255)),
		u8(clamp(f32(surface_color[2]) * b, 0, 255)),
		surface_color[3],
	}
}

// Simplified lighting for points without normals — uses position-based brightness
// Good for point clouds and voxel-style rendering
light_point_simple :: proc(l: ^Lighting, surface_color: [4]u8, point: rl.Vector3) -> [4]u8 {
	brightness: f32 = f32(l.ambient[0]) / 255.0 * 0.33 +
	                   f32(l.ambient[1]) / 255.0 * 0.33 +
	                   f32(l.ambient[2]) / 255.0 * 0.33

	for &light in l.lights {
		switch light.type {
		case .Directional:
			brightness += light.intensity * 0.5

		case .Point:
			dist := linalg.length(light.position - point)
			if dist > light.radius do continue
			attenuation := 1.0 - (dist / light.radius)
			brightness += light.intensity * attenuation
		}
	}

	return transmute([4]u8)rl.ColorBrightness(transmute(rl.Color)surface_color, clamp(brightness - 0.5, -0.5, 0.5))
}
