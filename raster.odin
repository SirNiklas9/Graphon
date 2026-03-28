package main

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

// A 3D triangle with vertices and a color
Triangle3D :: struct {
	v0, v1, v2: rl.Vector3,
	color:      [4]u8,
}

// Projected 2D triangle (screen space cells + depth)
ProjectedVert :: struct {
	col:   f32,
	row:   f32,
	depth: f32,
}

// Calculate face normal from triangle vertices
triangle_normal :: proc(t: ^Triangle3D) -> rl.Vector3 {
	edge1 := t.v1 - t.v0
	edge2 := t.v2 - t.v0
	return linalg.normalize(linalg.cross(edge1, edge2))
}

// Rasterize a 3D triangle onto the grid with depth testing, fog, and lighting
raster_triangle :: proc(
	grid: ^Grid, db: ^DepthBuffer, cam: ^Camera,
	tri: ^Triangle3D,
	lights: ^Lighting,
	fog_color: [4]u8 = {32, 32, 32, 255},
	fog_start: f32 = 20, fog_end: f32 = 60,
) {
	// Project all 3 vertices
	p0, ok0 := project_vert(grid, cam, tri.v0)
	p1, ok1 := project_vert(grid, cam, tri.v1)
	p2, ok2 := project_vert(grid, cam, tri.v2)

	// All vertices must be in front of camera (no near-plane clipping yet)
	if !ok0 || !ok1 || !ok2 do return

	// Face normal for lighting
	normal := triangle_normal(tri)

	// Bounding box in cell space
	min_col := math.floor(min(p0.col, p1.col, p2.col))
	max_col := math.ceil(max(p0.col, p1.col, p2.col))
	min_row := math.floor(min(p0.row, p1.row, p2.row))
	max_row := math.ceil(max(p0.row, p1.row, p2.row))

	// Clamp to grid
	c0 := int(max(min_col, 0))
	c1 := int(min(max_col, f32(grid.cols - 1)))
	r0 := int(max(min_row, 0))
	r1 := int(min(max_row, f32(grid.rows - 1)))

	// Scanline fill using barycentric coordinates
	for row in r0 ..= r1 {
		for col in c0 ..= c1 {
			px := f32(col) + 0.5
			py := f32(row) + 0.5

			// Barycentric coordinates
			u, v, w := barycentric(px, py, p0, p1, p2)
			if u < 0 || v < 0 || w < 0 do continue

			// Interpolate depth
			depth := u * p0.depth + v * p1.depth + w * p2.depth

			if !depth_test(db, col, row, depth) do continue

			// Interpolate 3D position for lighting
			world_pos := rl.Vector3{
				u * tri.v0.x + v * tri.v1.x + w * tri.v2.x,
				u * tri.v0.y + v * tri.v1.y + w * tri.v2.y,
				u * tri.v0.z + v * tri.v1.z + w * tri.v2.z,
			}

			// Light the surface
			lit_color: [4]u8
			if lights != nil {
				lit_color = light_point(lights, tri.color, world_pos, normal)
			} else {
				lit_color = tri.color
			}

			// Apply fog
			fog_factor := clamp((depth - fog_start) / (fog_end - fog_start), 0.0, 1.0)
			final_color := transmute([4]u8)rl.ColorLerp(
				transmute(rl.Color)lit_color,
				transmute(rl.Color)fog_color,
				fog_factor,
			)

			grid_set(grid, col, row, Grafel{char = '█', fg = final_color, bg = final_color})
		}
	}
}

// Project a single vertex to screen cell space
project_vert :: proc(grid: ^Grid, cam: ^Camera, point: rl.Vector3) -> (ProjectedVert, bool) {
	screen := rl.GetWorldToScreen(point, cam.rl_cam)

	dir := point - cam.rl_cam.position
	forward := cam.rl_cam.target - cam.rl_cam.position
	dot := dir.x * forward.x + dir.y * forward.y + dir.z * forward.z
	if dot <= 0 do return {}, false

	return ProjectedVert{
		col   = screen.x / grid.cell_w,
		row   = screen.y / grid.cell_h,
		depth = linalg.length(point - cam.rl_cam.position),
	}, true
}

// Barycentric coordinates for point (px, py) in triangle (p0, p1, p2)
barycentric :: proc(px, py: f32, p0, p1, p2: ProjectedVert) -> (u, v, w: f32) {
	v0x := p1.col - p0.col
	v0y := p1.row - p0.row
	v1x := p2.col - p0.col
	v1y := p2.row - p0.row
	v2x := px - p0.col
	v2y := py - p0.row

	den := v0x * v1y - v1x * v0y
	if abs(den) < 1e-10 do return -1, -1, -1 // degenerate

	inv := 1.0 / den
	v = (v2x * v1y - v1x * v2y) * inv
	w = (v0x * v2y - v2x * v0y) * inv
	u = 1.0 - v - w
	return u, v, w
}

// Helper: build a quad from 4 points as 2 triangles
raster_quad :: proc(
	grid: ^Grid, db: ^DepthBuffer, cam: ^Camera,
	v0, v1, v2, v3: rl.Vector3, color: [4]u8,
	lights: ^Lighting,
	fog_color: [4]u8 = {32, 32, 32, 255},
) {
	t1 := Triangle3D{v0 = v0, v1 = v1, v2 = v2, color = color}
	t2 := Triangle3D{v0 = v0, v1 = v2, v2 = v3, color = color}
	raster_triangle(grid, db, cam, &t1, lights, fog_color)
	raster_triangle(grid, db, cam, &t2, lights, fog_color)
}

// Helper: render a solid box (6 faces) at position with size
raster_box :: proc(
	grid: ^Grid, db: ^DepthBuffer, cam: ^Camera,
	pos: rl.Vector3, size: rl.Vector3, color: [4]u8,
	lights: ^Lighting,
	fog_color: [4]u8 = {32, 32, 32, 255},
) {
	hx := size.x * 0.5
	hy := size.y * 0.5
	hz := size.z * 0.5
	x, y, z := pos.x, pos.y, pos.z

	// 8 vertices
	v := [8]rl.Vector3{
		{x - hx, y - hy, z - hz}, // 0: left  bottom back
		{x + hx, y - hy, z - hz}, // 1: right bottom back
		{x + hx, y + hy, z - hz}, // 2: right top    back
		{x - hx, y + hy, z - hz}, // 3: left  top    back
		{x - hx, y - hy, z + hz}, // 4: left  bottom front
		{x + hx, y - hy, z + hz}, // 5: right bottom front
		{x + hx, y + hy, z + hz}, // 6: right top    front
		{x - hx, y + hy, z + hz}, // 7: left  top    front
	}

	// 6 faces (each as a quad)
	raster_quad(grid, db, cam, v[4], v[5], v[6], v[7], color, lights, fog_color) // front
	raster_quad(grid, db, cam, v[1], v[0], v[3], v[2], color, lights, fog_color) // back
	raster_quad(grid, db, cam, v[3], v[7], v[6], v[2], color, lights, fog_color) // top
	raster_quad(grid, db, cam, v[0], v[1], v[5], v[4], color, lights, fog_color) // bottom
	raster_quad(grid, db, cam, v[0], v[4], v[7], v[3], color, lights, fog_color) // left
	raster_quad(grid, db, cam, v[5], v[1], v[2], v[6], color, lights, fog_color) // right
}

// Helper: render a rotated solid box
raster_box_rotated :: proc(
	grid: ^Grid, db: ^DepthBuffer, cam: ^Camera,
	pos: rl.Vector3, size: rl.Vector3, color: [4]u8,
	angle_y: f32,
	lights: ^Lighting,
	fog_color: [4]u8 = {32, 32, 32, 255},
) {
	hx := size.x * 0.5
	hy := size.y * 0.5
	hz := size.z * 0.5

	cos_a := math.cos(angle_y)
	sin_a := math.sin(angle_y)

	// Rotate a local point around Y then translate to world
	rot :: proc(lx, ly, lz, px, py, pz, cos_a, sin_a: f32) -> rl.Vector3 {
		rx := lx * cos_a - lz * sin_a
		rz := lx * sin_a + lz * cos_a
		return {rx + px, ly + py, rz + pz}
	}

	v := [8]rl.Vector3{
		rot(-hx, -hy, -hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(+hx, -hy, -hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(+hx, +hy, -hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(-hx, +hy, -hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(-hx, -hy, +hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(+hx, -hy, +hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(+hx, +hy, +hz, pos.x, pos.y, pos.z, cos_a, sin_a),
		rot(-hx, +hy, +hz, pos.x, pos.y, pos.z, cos_a, sin_a),
	}

	raster_quad(grid, db, cam, v[4], v[5], v[6], v[7], color, lights, fog_color)
	raster_quad(grid, db, cam, v[1], v[0], v[3], v[2], color, lights, fog_color)
	raster_quad(grid, db, cam, v[3], v[7], v[6], v[2], color, lights, fog_color)
	raster_quad(grid, db, cam, v[0], v[1], v[5], v[4], color, lights, fog_color)
	raster_quad(grid, db, cam, v[0], v[4], v[7], v[3], color, lights, fog_color)
	raster_quad(grid, db, cam, v[5], v[1], v[2], v[6], color, lights, fog_color)
}
