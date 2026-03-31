package main

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

// 3D camera wrapper with WASD + mouse control
Camera :: struct {
	rl_cam:     rl.Camera3D,
	move_speed: f32,
	look_speed: f32,
	yaw:        f32,
	pitch:      f32,
}

camera_create :: proc(pos: rl.Vector3 = {0, 5, 10}, target: rl.Vector3 = {0, 0, 0}) -> Camera {
	cam := Camera{
		move_speed = 10.0,
		look_speed = 0.003,
	}
	cam.rl_cam = rl.Camera3D{
		position   = pos,
		target     = target,
		up         = {0, 1, 0},
		fovy       = 60.0,
		projection = .PERSPECTIVE,
	}
	dir := linalg.normalize(target - pos)
	cam.yaw = math.atan2(dir.x, dir.z)
	cam.pitch = math.asin(clamp(dir.y, -0.99, 0.99))
	return cam
}

camera_update :: proc(cam: ^Camera, dt: f32) {
	if rl.IsMouseButtonDown(.RIGHT) {
		delta := rl.GetMouseDelta()
		cam.yaw -= delta.x * cam.look_speed
		cam.pitch -= delta.y * cam.look_speed
		cam.pitch = clamp(cam.pitch, -1.4, 1.4)
	}

	forward := rl.Vector3{
		math.sin(cam.yaw) * math.cos(cam.pitch),
		math.sin(cam.pitch),
		math.cos(cam.yaw) * math.cos(cam.pitch),
	}
	right := linalg.normalize(linalg.cross(forward, rl.Vector3{0, 1, 0}))
	up := rl.Vector3{0, 1, 0}

	speed := cam.move_speed * dt

	if rl.IsKeyDown(.W) { cam.rl_cam.position += forward * speed }
	if rl.IsKeyDown(.S) { cam.rl_cam.position -= forward * speed }
	if rl.IsKeyDown(.A) { cam.rl_cam.position -= right * speed }
	if rl.IsKeyDown(.D) { cam.rl_cam.position += right * speed }
	if rl.IsKeyDown(.Q) || rl.IsKeyDown(.LEFT_CONTROL) { cam.rl_cam.position -= up * speed }
	if rl.IsKeyDown(.E) || rl.IsKeyDown(.SPACE) { cam.rl_cam.position += up * speed }

	cam.rl_cam.target = cam.rl_cam.position + forward
}
