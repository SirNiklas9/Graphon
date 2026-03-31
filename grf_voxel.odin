package main

import rl "vendor:raylib"

// Build a 3D grid from voxel layers: cell value is the rune at that position,
// or 0 for air. Returns a flat slice [y * size_x * size_z + z * size_x + x].
@(private = "file")
_voxel_build_grid :: proc(voxel: ^GrfVoxel) -> []rune {
	total := voxel.size_x * voxel.size_y * voxel.size_z
	grid := make([]rune, total)

	for &layer in voxel.layers {
		y := layer.index
		if y < 0 || y >= voxel.size_y do continue

		for zi := 0; zi < len(layer.rows); zi += 1 {
			z := zi
			if z >= voxel.size_z do break

			row_runes := _string_to_runes(layer.rows[zi])
			defer delete(row_runes)

			for xi := 0; xi < len(row_runes); xi += 1 {
				x := xi
				if x >= voxel.size_x do break

				ch := row_runes[xi]
				if ch == '.' {
					grid[y * voxel.size_x * voxel.size_z + z * voxel.size_x + x] = 0
				} else {
					grid[y * voxel.size_x * voxel.size_z + z * voxel.size_x + x] = ch
				}
			}
		}
	}

	return grid
}

@(private = "file")
_string_to_runes :: proc(s: string) -> []rune {
	result := make([dynamic]rune)
	for ch in s {
		append(&result, ch)
	}
	return result[:]
}

@(private = "file")
_grid_at :: proc(grid: []rune, voxel: ^GrfVoxel, x, y, z: int) -> rune {
	if x < 0 || x >= voxel.size_x do return 0
	if y < 0 || y >= voxel.size_y do return 0
	if z < 0 || z >= voxel.size_z do return 0
	return grid[y * voxel.size_x * voxel.size_z + z * voxel.size_x + x]
}

// Face direction enum for the 6 cube faces
@(private = "file")
FaceDir :: enum {
	PosX,
	NegX,
	PosY,
	NegY,
	PosZ,
	NegZ,
}

// Per-face normal vectors
@(private = "file")
FACE_NORMALS :: [FaceDir][3]f32{
	.PosX = { 1,  0,  0},
	.NegX = {-1,  0,  0},
	.PosY = { 0,  1,  0},
	.NegY = { 0, -1,  0},
	.PosZ = { 0,  0,  1},
	.NegZ = { 0,  0, -1},
}

// Per-face vertex offsets (4 corners, wound CCW when viewed from outside)
// Each face has 4 vertices -> 2 triangles -> indices 0,1,2, 0,2,3
@(private = "file")
FACE_VERTS :: [FaceDir][4][3]f32{
	.PosX = {{1,0,0}, {1,1,0}, {1,1,1}, {1,0,1}},
	.NegX = {{0,0,1}, {0,1,1}, {0,1,0}, {0,0,0}},
	.PosY = {{0,1,0}, {0,1,1}, {1,1,1}, {1,1,0}},
	.NegY = {{0,0,1}, {0,0,0}, {1,0,0}, {1,0,1}},
	.PosZ = {{1,0,1}, {1,1,1}, {0,1,1}, {0,0,1}},
	.NegZ = {{0,0,0}, {0,1,0}, {1,1,0}, {1,0,0}},
}

// Neighbor offsets per face direction
@(private = "file")
FACE_NEIGHBOR :: [FaceDir][3]int{
	.PosX = { 1,  0,  0},
	.NegX = {-1,  0,  0},
	.PosY = { 0,  1,  0},
	.NegY = { 0, -1,  0},
	.PosZ = { 0,  0,  1},
	.NegZ = { 0,  0, -1},
}

// Triangle indices for a quad (4 corners -> 2 tris -> 6 verts)
@(private = "file")
QUAD_INDICES :: [6]int{0, 1, 2, 0, 2, 3}

// Convert voxel data into a Raylib model with vertex-colored mesh.
grf_voxel_to_model :: proc(voxel: ^GrfVoxel) -> rl.Model {
	grid := _voxel_build_grid(voxel)
	defer delete(grid)

	// First pass: count visible faces
	face_count := 0
	for y in 0 ..< voxel.size_y {
		for z in 0 ..< voxel.size_z {
			for x in 0 ..< voxel.size_x {
				ch := grid[y * voxel.size_x * voxel.size_z + z * voxel.size_x + x]
				if ch == 0 do continue

				for dir in FaceDir {
					neighbors := FACE_NEIGHBOR
					nb := neighbors[dir]
					if _grid_at(grid, voxel, x + nb[0], y + nb[1], z + nb[2]) == 0 {
						face_count += 1
					}
				}
			}
		}
	}

	// 6 vertices per face (2 triangles)
	vert_count := face_count * 6
	tri_count := face_count * 2

	// Allocate arrays
	vert_bytes := vert_count * 3 * size_of(f32)
	color_bytes := vert_count * 4 * size_of(u8)
	vertices := cast([^]f32)raw_data(make([]u8, vert_bytes))
	normals  := cast([^]f32)raw_data(make([]u8, vert_bytes))
	colors   := raw_data(make([]u8, color_bytes))

	// Second pass: emit geometry
	vi := 0 // vertex index
	for y in 0 ..< voxel.size_y {
		for z in 0 ..< voxel.size_z {
			for x in 0 ..< voxel.size_x {
				ch := grid[y * voxel.size_x * voxel.size_z + z * voxel.size_x + x]
				if ch == 0 do continue

				// Look up color from palette
				color := rl.WHITE
				if ch in voxel.palette {
					color = voxel.palette[ch]
				}

				for dir in FaceDir {
					neighbors := FACE_NEIGHBOR
					nb := neighbors[dir]
					if _grid_at(grid, voxel, x + nb[0], y + nb[1], z + nb[2]) != 0 {
						continue
					}

					verts := FACE_VERTS
					norms := FACE_NORMALS
					quads := QUAD_INDICES
					corners := verts[dir]
					normal := norms[dir]

					for qi in 0 ..< 6 {
						ci := quads[qi]
						corner := corners[ci]

						// Position: voxel origin + corner offset
						vertices[vi * 3 + 0] = f32(x) + corner[0]
						vertices[vi * 3 + 1] = f32(y) + corner[1]
						vertices[vi * 3 + 2] = f32(z) + corner[2]

						// Normal
						normals[vi * 3 + 0] = normal[0]
						normals[vi * 3 + 1] = normal[1]
						normals[vi * 3 + 2] = normal[2]

						// Vertex color (RGBA)
						colors[vi * 4 + 0] = color.r
						colors[vi * 4 + 1] = color.g
						colors[vi * 4 + 2] = color.b
						colors[vi * 4 + 3] = color.a

						vi += 1
					}
				}
			}
		}
	}

	mesh := rl.Mesh{
		vertexCount   = i32(vert_count),
		triangleCount = i32(tri_count),
		vertices      = vertices,
		normals       = normals,
		colors        = colors,
	}

	rl.UploadMesh(&mesh, false)
	return rl.LoadModelFromMesh(mesh)
}

// Unload a voxel model and its mesh data.
grf_voxel_model_destroy :: proc(model: ^rl.Model) {
	rl.UnloadModel(model^)
}
