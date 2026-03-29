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
	// Calculate initial yaw/pitch from direction
	dir := linalg.normalize(target - pos)
	cam.yaw = math.atan2(dir.x, dir.z)
	cam.pitch = math.asin(clamp(dir.y, -0.99, 0.99))
	return cam
}

camera_update :: proc(cam: ^Camera, dt: f32) {
	// Mouse look (right mouse button held)
	if rl.IsMouseButtonDown(.RIGHT) {
		delta := rl.GetMouseDelta()
		cam.yaw -= delta.x * cam.look_speed
		cam.pitch -= delta.y * cam.look_speed
		cam.pitch = clamp(cam.pitch, -1.4, 1.4) // ~80 degrees
	}

	// Direction vectors
	forward := rl.Vector3{
		math.sin(cam.yaw) * math.cos(cam.pitch),
		math.sin(cam.pitch),
		math.cos(cam.yaw) * math.cos(cam.pitch),
	}
	right := linalg.normalize(linalg.cross(forward, rl.Vector3{0, 1, 0}))
	up := rl.Vector3{0, 1, 0}

	speed := cam.move_speed * dt

	// WASD movement
	if rl.IsKeyDown(.W) { cam.rl_cam.position += forward * speed }
	if rl.IsKeyDown(.S) { cam.rl_cam.position -= forward * speed }
	if rl.IsKeyDown(.A) { cam.rl_cam.position -= right * speed }
	if rl.IsKeyDown(.D) { cam.rl_cam.position += right * speed }
	if rl.IsKeyDown(.Q) { cam.rl_cam.position -= up * speed }
	if rl.IsKeyDown(.E) { cam.rl_cam.position += up * speed }

	// Update target from yaw/pitch
	cam.rl_cam.target = cam.rl_cam.position + forward
}

// Depth buffer — one f32 per cell, initialized to max depth
DepthBuffer :: struct {
	data: []f32,
	cols: int,
	rows: int,
}

depth_buffer_create :: proc(cols, rows: int) -> DepthBuffer {
	db := DepthBuffer{
		data = make([]f32, cols * rows),
		cols = cols,
		rows = rows,
	}
	depth_buffer_clear(&db)
	return db
}

depth_buffer_destroy :: proc(db: ^DepthBuffer) {
	delete(db.data)
}

depth_buffer_clear :: proc(db: ^DepthBuffer) {
	for i in 0 ..< len(db.data) {
		db.data[i] = 1e30 // far plane
	}
}

depth_buffer_resize :: proc(db: ^DepthBuffer, cols, rows: int) {
	delete(db.data)
	db.data = make([]f32, cols * rows)
	db.cols = cols
	db.rows = rows
	depth_buffer_clear(db)
}

// Test and write depth — returns true if this point is closer than what's stored
depth_test :: proc(db: ^DepthBuffer, col, row: int, depth: f32) -> bool {
	if col < 0 || col >= db.cols || row < 0 || row >= db.rows do return false
	idx := row * db.cols + col
	if depth < db.data[idx] {
		db.data[idx] = depth
		return true
	}
	return false
}

// Project a 3D world point to grid cell + depth
project_3d :: proc(grid: ^Grid, cam: ^Camera, point: rl.Vector3) -> (col: int, row: int, depth: f32, visible: bool) {
	screen := rl.GetWorldToScreen(point, cam.rl_cam)

	// Check if point is behind camera
	dir := point - cam.rl_cam.position
	forward := cam.rl_cam.target - cam.rl_cam.position
	dot := dir.x * forward.x + dir.y * forward.y + dir.z * forward.z
	if dot <= 0 do return 0, 0, 0, false

	col = int(screen.x / grid.cell_w)
	row = int(screen.y / grid.cell_h)
	depth = linalg.length(point - cam.rl_cam.position)
	visible = col >= 0 && col < grid.cols && row >= 0 && row < grid.rows

	return col, row, depth, visible
}

// Plot a 3D point onto the grid with depth testing and fog
plot_3d :: proc(grid: ^Grid, db: ^DepthBuffer, cam: ^Camera, point: rl.Vector3, color: [4]u8, fog_color: [4]u8 = {0, 0, 0, 255}, fog_start: f32 = 20, fog_end: f32 = 60) {
	col, row, depth, visible := project_3d(grid, cam, point)
	if !visible do return
	if !depth_test(db, col, row, depth) do return

	// Depth fog — lerp toward fog color based on distance
	fog_factor := clamp((depth - fog_start) / (fog_end - fog_start), 0.0, 1.0)
	fogged := transmute([4]u8)rl.ColorLerp(transmute(rl.Color)color, transmute(rl.Color)fog_color, fog_factor)

	brightness := (f32(fogged[0]) * 0.299 + f32(fogged[1]) * 0.587 + f32(fogged[2]) * 0.114) / 255.0
	grid_set(grid, col, row, solve_cell(fogged, brightness, fog_color))
}

// Volume — a 3D region with fog/ambient properties
Volume :: struct {
	min_pos:    rl.Vector3,
	max_pos:    rl.Vector3,
	fog_color:  [4]u8,
	fog_density: f32,
	ambient:    [4]u8,
}

// Check if a point is inside a volume
point_in_volume :: proc(v: ^Volume, point: rl.Vector3) -> bool {
	return point.x >= v.min_pos.x && point.x <= v.max_pos.x &&
	       point.y >= v.min_pos.y && point.y <= v.max_pos.y &&
	       point.z >= v.min_pos.z && point.z <= v.max_pos.z
}

// Sample volume properties at a point — returns fog color and density if inside
sample_volume :: proc(volumes: []Volume, point: rl.Vector3) -> (fog_color: [4]u8, fog_density: f32, ambient: [4]u8, in_volume: bool) {
	for &v in volumes {
		if point_in_volume(&v, point) {
			return v.fog_color, v.fog_density, v.ambient, true
		}
	}
	return {0, 0, 0, 255}, 0.0, {0, 0, 0, 0}, false
}
