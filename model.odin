package main

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

// Load a model file and render it to the grid via triangle rasterization
GraphonModel :: struct {
	model:  rl.Model,
	loaded: bool,
}

model_load :: proc(path: cstring) -> GraphonModel {
	model := rl.LoadModel(path)
	return GraphonModel{
		model  = model,
		loaded = model.meshCount > 0,
	}
}

model_destroy :: proc(gm: ^GraphonModel) {
	if gm.loaded {
		rl.UnloadModel(gm.model)
		gm.loaded = false
	}
}

// Render a model to the grid using the triangle rasterizer
model_render :: proc(
	gm: ^GraphonModel,
	grid: ^Grid, db: ^DepthBuffer, cam: ^Camera,
	position: rl.Vector3,
	scale: f32,
	rotation_y: f32,
	color: [4]u8,
	lights: ^Lighting = nil,
	fog_color: [4]u8 = {32, 32, 32, 255},
) {
	if !gm.loaded do return

	cos_a := math.cos(rotation_y)
	sin_a := math.sin(rotation_y)

	for mesh_idx in 0 ..< gm.model.meshCount {
		mesh := gm.model.meshes[mesh_idx]

		if mesh.vertexCount == 0 || mesh.vertices == nil do continue

		// Get vertex data
		verts := mesh.vertices
		vert_count := int(mesh.vertexCount)

		// Check if we have indices
		has_indices := mesh.indices != nil && mesh.triangleCount > 0
		tri_count := has_indices ? int(mesh.triangleCount) : vert_count / 3

		for tri in 0 ..< tri_count {
			// Get vertex indices for this triangle
			i0, i1, i2: int
			if has_indices {
				i0 = int(mesh.indices[tri * 3 + 0])
				i1 = int(mesh.indices[tri * 3 + 1])
				i2 = int(mesh.indices[tri * 3 + 2])
			} else {
				i0 = tri * 3 + 0
				i1 = tri * 3 + 1
				i2 = tri * 3 + 2
			}

			// Get vertex positions (3 floats per vertex)
			v0 := rl.Vector3{verts[i0*3+0], verts[i0*3+1], verts[i0*3+2]}
			v1 := rl.Vector3{verts[i1*3+0], verts[i1*3+1], verts[i1*3+2]}
			v2 := rl.Vector3{verts[i2*3+0], verts[i2*3+1], verts[i2*3+2]}

			// Apply scale
			v0 *= scale
			v1 *= scale
			v2 *= scale

			// Apply Y rotation
			v0 = rl.Vector3{
				v0.x * cos_a - v0.z * sin_a,
				v0.y,
				v0.x * sin_a + v0.z * cos_a,
			}
			v1 = rl.Vector3{
				v1.x * cos_a - v1.z * sin_a,
				v1.y,
				v1.x * sin_a + v1.z * cos_a,
			}
			v2 = rl.Vector3{
				v2.x * cos_a - v2.z * sin_a,
				v2.y,
				v2.x * sin_a + v2.z * cos_a,
			}

			// Apply position offset
			v0 += position
			v1 += position
			v2 += position

			// Rasterize the triangle
			triangle := Triangle3D{
				v0 = v0, v1 = v1, v2 = v2,
				color = color,
			}
			raster_triangle(grid, db, cam, &triangle, lights, fog_color)
		}
	}
}

// Render a model with per-mesh colors from the model's materials
model_render_colored :: proc(
	gm: ^GraphonModel,
	grid: ^Grid, db: ^DepthBuffer, cam: ^Camera,
	position: rl.Vector3,
	scale: f32,
	rotation_y: f32,
	lights: ^Lighting = nil,
	fog_color: [4]u8 = {32, 32, 32, 255},
) {
	if !gm.loaded do return

	cos_a := math.cos(rotation_y)
	sin_a := math.sin(rotation_y)

	for mesh_idx in 0 ..< gm.model.meshCount {
		mesh := gm.model.meshes[mesh_idx]
		if mesh.vertexCount == 0 || mesh.vertices == nil do continue

		// Get material color for this mesh
		mat_idx := gm.model.meshMaterial[mesh_idx]
		mat := gm.model.materials[mat_idx]
		mat_color := mat.maps[rl.MaterialMapIndex.ALBEDO].color
		color := [4]u8{mat_color.r, mat_color.g, mat_color.b, mat_color.a}

		verts := mesh.vertices
		vert_count := int(mesh.vertexCount)
		has_indices := mesh.indices != nil && mesh.triangleCount > 0
		tri_count := has_indices ? int(mesh.triangleCount) : vert_count / 3

		for tri in 0 ..< tri_count {
			i0, i1, i2: int
			if has_indices {
				i0 = int(mesh.indices[tri * 3 + 0])
				i1 = int(mesh.indices[tri * 3 + 1])
				i2 = int(mesh.indices[tri * 3 + 2])
			} else {
				i0 = tri * 3 + 0
				i1 = tri * 3 + 1
				i2 = tri * 3 + 2
			}

			v0 := rl.Vector3{verts[i0*3+0], verts[i0*3+1], verts[i0*3+2]}
			v1 := rl.Vector3{verts[i1*3+0], verts[i1*3+1], verts[i1*3+2]}
			v2 := rl.Vector3{verts[i2*3+0], verts[i2*3+1], verts[i2*3+2]}

			v0 *= scale; v1 *= scale; v2 *= scale

			v0 = rl.Vector3{v0.x*cos_a - v0.z*sin_a, v0.y, v0.x*sin_a + v0.z*cos_a}
			v1 = rl.Vector3{v1.x*cos_a - v1.z*sin_a, v1.y, v1.x*sin_a + v1.z*cos_a}
			v2 = rl.Vector3{v2.x*cos_a - v2.z*sin_a, v2.y, v2.x*sin_a + v2.z*cos_a}

			v0 += position; v1 += position; v2 += position

			triangle := Triangle3D{v0 = v0, v1 = v1, v2 = v2, color = color}
			raster_triangle(grid, db, cam, &triangle, lights, fog_color)
		}
	}
}
