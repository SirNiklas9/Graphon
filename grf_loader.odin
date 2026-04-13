package main

import rl "vendor:raylib"
import "core:strings"
import "core:path/filepath"
import "core:fmt"

MAX_INCLUDE_DEPTH :: 8

// Load a .grf scene file and build a Scene from it
// Returns the scene and a list of loaded models (caller must unload)
GrfLoadedScene :: struct {
	scene:  Scene,
	models: [dynamic]rl.Model,  // all loaded models (for cleanup)
}

grf_load_scene :: proc(path: string) -> (GrfLoadedScene, bool) {
	loaded := GrfLoadedScene{
		scene = scene_create(),
	}

	grf, ok := grf_parse(path)
	if !ok {
		rl.TraceLog(.WARNING, "Failed to parse .grf file: %s", strings.clone_to_cstring(path))
		return loaded, false
	}
	defer grf_file_destroy(&grf)

	visited := make(map[string]bool)
	defer delete(visited)
	visited[path] = true

	base_dir := filepath.dir(path)

	switch &d in grf.data {
	case GrfScene:
		// Camera
		loaded.scene.camera = camera_create(d.camera_pos, d.camera_target)

		// Atmosphere
		loaded.scene.fog_color = {d.fog_color.x, d.fog_color.y, d.fog_color.z}
		loaded.scene.fog_start = d.fog_start
		loaded.scene.fog_end = d.fog_end
		loaded.scene.fog_enabled = d.fog_enabled
		if d.ambient != {} {
			loaded.scene.ambient = {d.ambient.x, d.ambient.y, d.ambient.z}
		}

		// Lights
		for &light in d.lights {
			scene_add_light(&loaded.scene, light.type, light.position, light.target, light.color)
		}

		// Volumes
		for &vol in d.volumes {
			scene_add_volume(&loaded.scene, vol.min_pos, vol.max_pos, vol.color, vol.density)
		}

		// Includes
		for &inc in d.includes {
			inc_path := resolve_path(base_dir, inc.path)
			grf_load_include(&loaded, inc_path, inc.position, inc.scale, inc.rotate, &visited, 0)
		}

	case GrfObject:
		// Single object file — create a default scene around it
		grf_load_object(&loaded, &d, {0, 0, 0}, 1.0, 0.0, path)

	case GrfVoxel:
		// Single voxel file — create scene with the voxel model
		model := grf_voxel_to_model(&d)
		append(&loaded.models, model)
		scene_add_model(&loaded.scene, model, {0, 0, 0}, material_create(rl.WHITE), 1.0)

	case GrfGrafel:
		// 2D grafel → render to texture → billboard in 3D
		model, ok_g := grafel_to_billboard(&d)
		if ok_g {
			append(&loaded.models, model)
			scene_add_model(&loaded.scene, model, {0, 0, 0}, material_create(rl.WHITE), 1.0)
			loaded.scene.objects[len(loaded.scene.objects) - 1].billboard = true
		}
	}

	return loaded, true
}

// Load an included .grf file into the scene
grf_load_include :: proc(loaded: ^GrfLoadedScene, path: string, pos: rl.Vector3, scale: f32, rotate: f32, visited: ^map[string]bool, depth: int) {
	if depth >= MAX_INCLUDE_DEPTH {
		rl.TraceLog(.WARNING, "Max include depth reached for: %s", strings.clone_to_cstring(path))
		return
	}

	if path in visited^ {
		rl.TraceLog(.WARNING, "Circular include detected: %s", strings.clone_to_cstring(path))
		return
	}
	visited[path] = true
	defer delete_key(visited, path)

	grf, ok := grf_parse(path)
	if !ok {
		rl.TraceLog(.WARNING, "Failed to load include: %s", strings.clone_to_cstring(path))
		return
	}
	defer grf_file_destroy(&grf)

	base_dir := filepath.dir(path)

	switch &d in grf.data {
	case GrfObject:
		grf_load_object(loaded, &d, pos, scale, rotate, path)

	case GrfVoxel:
		model := grf_voxel_to_model(&d)
		append(&loaded.models, model)
		scene_add_model(&loaded.scene, model, pos, material_create(rl.WHITE), scale)

	case GrfGrafel:
		model, ok_g := grafel_to_billboard(&d)
		if ok_g {
			append(&loaded.models, model)
			mat := material_create(rl.WHITE, 0.0, 1.0)
			idx := scene_add_model(&loaded.scene, model, pos, mat, scale)
			if idx >= 0 {
				loaded.scene.objects[idx].billboard = true
			}
		}

	case GrfScene:
		// Sub-scene — flatten into parent with position offset
		for &light in d.lights {
			offset_pos := rl.Vector3{light.position.x + pos.x, light.position.y + pos.y, light.position.z + pos.z}
			scene_add_light(&loaded.scene, light.type, offset_pos, light.target, light.color)
		}
		for &vol in d.volumes {
			offset_min := rl.Vector3{vol.min_pos.x + pos.x, vol.min_pos.y + pos.y, vol.min_pos.z + pos.z}
			offset_max := rl.Vector3{vol.max_pos.x + pos.x, vol.max_pos.y + pos.y, vol.max_pos.z + pos.z}
			scene_add_volume(&loaded.scene, offset_min, offset_max, vol.color, vol.density)
		}
		for &inc in d.includes {
			inc_path := resolve_path(base_dir, inc.path)
			offset_pos := rl.Vector3{inc.position.x + pos.x, inc.position.y + pos.y, inc.position.z + pos.z}
			grf_load_include(loaded, inc_path, offset_pos, inc.scale * scale, inc.rotate + rotate, visited, depth + 1)
		}
	}
}

// Load an object definition into the scene
grf_load_object :: proc(loaded: ^GrfLoadedScene, obj: ^GrfObject, pos: rl.Vector3, scale: f32, rotate: f32, src_path: string) {
	base_dir := filepath.dir(src_path)

	if obj.model_path != "" {
		// 3D model
		model_path := resolve_path(base_dir, obj.model_path)
		cpath := strings.clone_to_cstring(model_path)
		model := rl.LoadModel(cpath)
		append(&loaded.models, model)

		mat := material_create(obj.color, obj.specular, obj.roughness)

		// Load normal map if specified
		if obj.normal_path != "" {
			nmap_path := resolve_path(base_dir, obj.normal_path)
			ncpath := strings.clone_to_cstring(nmap_path)
			mat.normal_map = rl.LoadTexture(ncpath)
		}

		idx := scene_add_model(&loaded.scene, model, pos, mat, scale)
		if idx >= 0 {
			loaded.scene.objects[idx].rotation_y = rotate * 0.01745329 // deg to rad
			loaded.scene.objects[idx].billboard = obj.billboard
		}
	} else if obj.sprite_path != "" {
		// 2D sprite as billboard
		sprite_path := resolve_path(base_dir, obj.sprite_path)
		cpath := strings.clone_to_cstring(sprite_path)
		tex := rl.LoadTexture(cpath)

		mesh := rl.GenMeshPlane(2, 2, 1, 1)
		model := rl.LoadModelFromMesh(mesh)
		model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = tex
		append(&loaded.models, model)

		mat := material_create(rl.WHITE, 0.0, 1.0)
		idx := scene_add_model(&loaded.scene, model, pos, mat, scale)
		if idx >= 0 {
			loaded.scene.objects[idx].billboard = obj.billboard
		}
	}
}

// Resolve a relative path against a base directory
resolve_path :: proc(base_dir, rel_path: string) -> string {
	if filepath.is_abs(rel_path) {
		return rel_path
	}
	result, _ := filepath.join({base_dir, rel_path}, context.allocator)
	return result
}

// Cleanup a loaded scene
grf_loaded_scene_destroy :: proc(ls: ^GrfLoadedScene) {
	for &model in ls.models {
		rl.UnloadModel(model)
	}
	delete(ls.models)
}
