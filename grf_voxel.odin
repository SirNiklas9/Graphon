package main

import rl "vendor:raylib"

// Build a 3D grid from voxel layers
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

FaceDir :: enum {
	PosX, NegX, PosY, NegY, PosZ, NegZ,
}

FACE_NORMALS :: [FaceDir][3]f32{
	.PosX = { 1,  0,  0},
	.NegX = {-1,  0,  0},
	.PosY = { 0,  1,  0},
	.NegY = { 0, -1,  0},
	.PosZ = { 0,  0,  1},
	.NegZ = { 0,  0, -1},
}

FACE_NEIGHBOR :: [FaceDir][3]int{
	.PosX = { 1,  0,  0},
	.NegX = {-1,  0,  0},
	.PosY = { 0,  1,  0},
	.NegY = { 0, -1,  0},
	.PosZ = { 0,  0,  1},
	.NegZ = { 0,  0, -1},
}

QUAD_INDICES :: [6]int{0, 1, 2, 0, 2, 3}

// Map (slice, u, v) to world (x, y, z) based on face direction
@(private = "file")
_to_world :: proc(dir: FaceDir, slice, u, v: int) -> (int, int, int) {
	switch dir {
	case .PosY, .NegY: return u, slice, v    // u=x, v=z
	case .PosX, .NegX: return slice, v, u    // u=z, v=y
	case .PosZ, .NegZ: return u, v, slice    // u=x, v=y
	}
	return 0, 0, 0
}

// Get the 4 corners for a merged quad, wound CCW when viewed from outside.
// These match the winding of the original FACE_VERTS for a 1x1 face.
@(private = "file")
_quad_corners :: proc(dir: FaceDir, slice, u0, v0, w, h: int) -> [4][3]f32 {
	s  := f32(slice)
	s1 := f32(slice + 1)
	fu := f32(u0)
	fv := f32(v0)
	fw := f32(u0 + w)
	fh := f32(v0 + h)

	switch dir {
	case .PosY: // top face at y=slice+1, u=x, v=z
		return {{fu,s1,fv}, {fu,s1,fh}, {fw,s1,fh}, {fw,s1,fv}}
	case .NegY: // bottom face at y=slice, u=x, v=z
		return {{fu,s,fh}, {fu,s,fv}, {fw,s,fv}, {fw,s,fh}}
	case .PosX: // right face at x=slice+1, u=z, v=y
		return {{s1,fv,fu}, {s1,fh,fu}, {s1,fh,fw}, {s1,fv,fw}}
	case .NegX: // left face at x=slice, u=z, v=y
		return {{s,fv,fw}, {s,fh,fw}, {s,fh,fu}, {s,fv,fu}}
	case .PosZ: // front face at z=slice+1, u=x, v=y
		return {{fw,fv,s1}, {fw,fh,s1}, {fu,fh,s1}, {fu,fv,s1}}
	case .NegZ: // back face at z=slice, u=x, v=y
		return {{fu,fv,s}, {fu,fh,s}, {fw,fh,s}, {fw,fv,s}}
	}
	return {}
}

// Convert voxel data into a Raylib model with greedy-meshed vertex-colored mesh.
grf_voxel_to_model :: proc(voxel: ^GrfVoxel) -> rl.Model {
	grid := _voxel_build_grid(voxel)
	defer delete(grid)

	// First pass: count visible faces (upper bound for greedy mesh)
	face_count := 0
	neighbors := FACE_NEIGHBOR
	for y in 0 ..< voxel.size_y {
		for z in 0 ..< voxel.size_z {
			for x in 0 ..< voxel.size_x {
				ch := grid[y * voxel.size_x * voxel.size_z + z * voxel.size_x + x]
				if ch == 0 do continue
				for dir in FaceDir {
					nb := neighbors[dir]
					if _grid_at(grid, voxel, x + nb[0], y + nb[1], z + nb[2]) == 0 {
						face_count += 1
					}
				}
			}
		}
	}

	// Allocate worst-case arrays (greedy mesh produces <= face_count quads)
	vert_count := face_count * 6
	vert_bytes := vert_count * 3 * size_of(f32)
	color_bytes := vert_count * 4 * size_of(u8)
	vertices := cast([^]f32)raw_data(make([]u8, vert_bytes))
	normals  := cast([^]f32)raw_data(make([]u8, vert_bytes))
	colors   := raw_data(make([]u8, color_bytes))

	vi := 0

	// For each face direction, sweep slices and greedy-merge same-color exposed faces
	norms := FACE_NORMALS
	quads := QUAD_INDICES
	for dir in FaceDir {
		nb := neighbors[dir]
		normal := norms[dir]

		// Determine axis sizes
		slice_size, u_size, v_size: int
		switch dir {
		case .PosY, .NegY: slice_size = voxel.size_y; u_size = voxel.size_x; v_size = voxel.size_z
		case .PosX, .NegX: slice_size = voxel.size_x; u_size = voxel.size_z; v_size = voxel.size_y
		case .PosZ, .NegZ: slice_size = voxel.size_z; u_size = voxel.size_x; v_size = voxel.size_y
		}

		visited := make([]bool, u_size * v_size)
		defer delete(visited)

		for slice in 0 ..< slice_size {
			// Clear visited
			for i in 0 ..< u_size * v_size { visited[i] = false }

			for v0 in 0 ..< v_size {
				for u0 in 0 ..< u_size {
					if visited[v0 * u_size + u0] do continue

					x, y, z := _to_world(dir, slice, u0, v0)
					ch := _grid_at(grid, voxel, x, y, z)
					if ch == 0 { continue }
					if _grid_at(grid, voxel, x + nb[0], y + nb[1], z + nb[2]) != 0 { continue }

					color := rl.WHITE
					if ch in voxel.palette { color = voxel.palette[ch] }

					// Greedy expand right (u direction)
					w := 1
					for u0 + w < u_size {
						if visited[v0 * u_size + u0 + w] do break
						nx, ny, nz := _to_world(dir, slice, u0 + w, v0)
						nch := _grid_at(grid, voxel, nx, ny, nz)
						if nch != ch do break
						if _grid_at(grid, voxel, nx + nb[0], ny + nb[1], nz + nb[2]) != 0 do break
						w += 1
					}

					// Greedy expand down (v direction)
					h := 1
					grow_v: for v0 + h < v_size {
						for du in 0 ..< w {
							if visited[(v0 + h) * u_size + u0 + du] do break grow_v
							nx, ny, nz := _to_world(dir, slice, u0 + du, v0 + h)
							nch := _grid_at(grid, voxel, nx, ny, nz)
							if nch != ch do break grow_v
							if _grid_at(grid, voxel, nx + nb[0], ny + nb[1], nz + nb[2]) != 0 do break grow_v
						}
						h += 1
					}

					// Mark visited
					for dv in 0 ..< h {
						for du in 0 ..< w {
							visited[(v0 + dv) * u_size + u0 + du] = true
						}
					}

					// Emit merged quad
					corners := _quad_corners(dir, slice, u0, v0, w, h)
					for qi in 0 ..< 6 {
						ci := quads[qi]
						c := corners[ci]
						vertices[vi * 3 + 0] = c[0]
						vertices[vi * 3 + 1] = c[1]
						vertices[vi * 3 + 2] = c[2]
						normals[vi * 3 + 0] = normal[0]
						normals[vi * 3 + 1] = normal[1]
						normals[vi * 3 + 2] = normal[2]
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
		vertexCount   = i32(vi),
		triangleCount = i32(vi / 3),
		vertices      = vertices,
		normals       = normals,
		colors        = colors,
	}

	rl.UploadMesh(&mesh, false)
	return rl.LoadModelFromMesh(mesh)
}

grf_voxel_model_destroy :: proc(model: ^rl.Model) {
	rl.UnloadModel(model^)
}
