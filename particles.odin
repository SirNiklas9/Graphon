package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"

// Visual particle data — the renderer only sees this
RenderParticle :: struct {
	position: rl.Vector3,
	color:    rl.Color,
	size:     f32,
}

// Draw particles as billboarded quads in the 3D scene
// Call this inside BeginMode3D/EndMode3D, after scene geometry
draw_particles :: proc(particles: []RenderParticle, cam: ^Camera) {
	if len(particles) == 0 do return

	// Enable additive blending for glow effect
	rlgl.SetBlendMode(i32(rl.BlendMode.ADDITIVE))
	rlgl.DisableDepthMask() // Don't write to depth — particles are transparent

	for &p in particles {
		if p.size <= 0 do continue
		draw_billboard_quad(p.position, p.size, p.color, cam)
	}

	rlgl.EnableDepthMask()
	rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA)) // Restore default
}

// Draw a single billboarded quad facing the camera
draw_billboard_quad :: proc(pos: rl.Vector3, size: f32, color: rl.Color, cam: ^Camera) {
	// Billboard vectors — always face camera
	forward := rl.Vector3{
		cam.rl_cam.position.x - pos.x,
		cam.rl_cam.position.y - pos.y,
		cam.rl_cam.position.z - pos.z,
	}
	// Normalize
	len := math.sqrt(forward.x*forward.x + forward.y*forward.y + forward.z*forward.z)
	if len < 0.001 do return
	forward.x /= len
	forward.y /= len
	forward.z /= len

	// Right and up vectors
	up := rl.Vector3{0, 1, 0}
	right := rl.Vector3{
		up.y * forward.z - up.z * forward.y,
		up.z * forward.x - up.x * forward.z,
		up.x * forward.y - up.y * forward.x,
	}
	// Normalize right
	rlen := math.sqrt(right.x*right.x + right.y*right.y + right.z*right.z)
	if rlen < 0.001 do return
	right.x /= rlen
	right.y /= rlen
	right.z /= rlen

	// Recalculate up
	up = rl.Vector3{
		forward.y * right.z - forward.z * right.y,
		forward.z * right.x - forward.x * right.z,
		forward.x * right.y - forward.y * right.x,
	}

	hs := size * 0.5 // half size

	// 4 corners of the billboard
	p1 := rl.Vector3{pos.x - right.x*hs - up.x*hs, pos.y - right.y*hs - up.y*hs, pos.z - right.z*hs - up.z*hs}
	p2 := rl.Vector3{pos.x + right.x*hs - up.x*hs, pos.y + right.y*hs - up.y*hs, pos.z + right.z*hs - up.z*hs}
	p3 := rl.Vector3{pos.x + right.x*hs + up.x*hs, pos.y + right.y*hs + up.y*hs, pos.z + right.z*hs + up.z*hs}
	p4 := rl.Vector3{pos.x - right.x*hs + up.x*hs, pos.y - right.y*hs + up.y*hs, pos.z - right.z*hs + up.z*hs}

	rl.DrawTriangle3D(p1, p2, p3, color)
	rl.DrawTriangle3D(p1, p3, p4, color)
}
