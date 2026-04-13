package main

import rl "vendor:raylib"
import "core:math"

MAX_SCENE_LIGHTS   :: 4
MAX_SCENE_VOLUMES  :: 4
MAX_SCENE_EMITTERS :: 16

// Material — defines how an object looks
Material :: struct {
	diffuse_color:  rl.Color,
	specular:       f32,        // 0-1 specular intensity
	roughness:      f32,        // 0-1 (0 = mirror, 1 = matte)
	diffuse_tex:    rl.Texture2D,
	normal_map:     rl.Texture2D,
}

material_default :: proc() -> Material {
	return Material{
		diffuse_color = rl.WHITE,
		specular      = 0.3,
		roughness     = 0.5,
	}
}

material_create :: proc(color: rl.Color, specular: f32 = 0.3, roughness: f32 = 0.5) -> Material {
	return Material{
		diffuse_color = color,
		specular      = specular,
		roughness     = roughness,
	}
}

// Scene light
SceneLight :: struct {
	enabled:  bool,
	type:     LightType,
	position: rl.Vector3,
	target:   rl.Vector3,
	color:    rl.Vector3,
}

// Scene volume
SceneVolume :: struct {
	enabled:  bool,
	min_pos:  rl.Vector3,
	max_pos:  rl.Vector3,
	color:    rl.Vector3,
	density:  f32,
}

// Scene — everything that exists in the world
Scene :: struct {
	// Objects (dynamic — heap allocated, no limit)
	objects:      [dynamic]Scene3DObject,

	// Lights
	lights:      [MAX_SCENE_LIGHTS]SceneLight,
	light_count: int,

	// Volumes
	volumes:      [MAX_SCENE_VOLUMES]SceneVolume,
	volume_count: int,

	// Camera
	camera: Camera,

	// Atmosphere
	fog_color:    rl.Vector3,
	fog_start:    f32,
	fog_end:      f32,
	fog_enabled:  bool,
	ambient:      rl.Vector3,
}

scene_create :: proc() -> Scene {
	return Scene{
		camera      = camera_create({0, 5, 12}, {0, 0, 0}),
		fog_color   = {0.05, 0.05, 0.08},
		fog_start   = 25,
		fog_end     = 60,
		fog_enabled = true,
		ambient     = {0.06, 0.06, 0.1},
	}
}

// Add a model to the scene. Returns the index.
scene_add_model :: proc(scene: ^Scene, model: rl.Model, position: rl.Vector3, mat: Material = {}, scale: f32 = 1.0) -> int {
	idx := len(scene.objects)

	// Apply diffuse texture to model materials if provided
	if mat.diffuse_tex.id != 0 {
		for mi in 0 ..< model.materialCount {
			model.materials[mi].maps[rl.MaterialMapIndex.ALBEDO].texture = mat.diffuse_tex
		}
	}

	// Compute bounding sphere from first mesh
	bounds_r: f32 = 2.0
	if model.meshCount > 0 {
		bb := rl.GetMeshBoundingBox(model.meshes[0])
		dx := bb.max.x - bb.min.x
		dy := bb.max.y - bb.min.y
		dz := bb.max.z - bb.min.z
		bounds_r = math.sqrt(dx*dx + dy*dy + dz*dz) * 0.5
	}

	append(&scene.objects, Scene3DObject{
		model             = model,
		loaded            = model.meshCount > 0,
		position          = position,
		scale             = scale,
		tint              = mat.diffuse_color != {} ? mat.diffuse_color : rl.WHITE,
		normal_map        = mat.normal_map,
		specular          = mat.specular,
		roughness         = mat.roughness,
		bounds_radius     = bounds_r,
		grafel_resolution = 1.0,
		parent            = -1,
		local_scale       = 1.0,
	})
	return idx
}

// Add a primitive cube to the scene
scene_add_cube :: proc(scene: ^Scene, position: rl.Vector3, size: rl.Vector3, color: rl.Color) -> int {
	idx := len(scene.objects)
	append(&scene.objects, Scene3DObject{
		loaded            = true,
		position          = position,
		scale             = 1.0,
		tint              = color,
		grafel_resolution = 1.0,
		parent            = -1,
		local_scale       = 1.0,
	})
	return idx
}

// Add a light to the scene. Returns the index.
scene_add_light :: proc(scene: ^Scene, type: LightType, position, target: rl.Vector3, color: rl.Vector3) -> int {
	if scene.light_count >= MAX_SCENE_LIGHTS do return -1
	idx := scene.light_count
	scene.lights[idx] = SceneLight{
		enabled  = true,
		type     = type,
		position = position,
		target   = target,
		color    = color,
	}
	scene.light_count += 1
	return idx
}

// Add a volume to the scene. Returns the index.
scene_add_volume :: proc(scene: ^Scene, min_pos, max_pos, color: rl.Vector3, density: f32) -> int {
	if scene.volume_count >= MAX_SCENE_VOLUMES do return -1
	idx := scene.volume_count
	scene.volumes[idx] = SceneVolume{
		enabled = true,
		min_pos = min_pos,
		max_pos = max_pos,
		color   = color,
		density = density,
	}
	scene.volume_count += 1
	return idx
}

// Remove an object by index
scene_remove_object :: proc(scene: ^Scene, idx: int) {
	if idx < 0 || idx >= len(scene.objects) do return
	ordered_remove(&scene.objects, idx)
}

// Apply scene data to the Scene3D renderer
scene3d_apply_scene :: proc(s3d: ^Scene3D, scene: ^Scene) {
	// Sync lights
	s3d.light_count = 0
	for i in 0 ..< scene.light_count {
		l := &scene.lights[i]
		scene3d_add_light(s3d, l.type, l.position, l.target, l.color)
	}

	// Sync volumes
	s3d.volume_count = 0
	for i in 0 ..< scene.volume_count {
		if s3d.volume_count >= 4 do break
		s3d.volumes[s3d.volume_count] = scene.volumes[i]
		s3d.volume_count += 1
	}
}

// Update scene hierarchy — propagate parent transforms to children.
// Call before rendering. Objects with parent >= 0 inherit position/rotation/scale.
scene_update_hierarchy :: proc(scene: ^Scene) {
	for i in 0 ..< len(scene.objects) {
		obj := &scene.objects[i]
		if obj.parent < 0 || obj.parent >= len(scene.objects) do continue

		p := &scene.objects[obj.parent]
		// Rotate child's local position around parent's Y axis
		sin_r := math.sin(p.rotation_y)
		cos_r := math.cos(p.rotation_y)
		lx := obj.local_position.x
		lz := obj.local_position.z

		obj.position = {
			p.position.x + (cos_r * lx - sin_r * lz) * p.scale,
			p.position.y + obj.local_position.y * p.scale,
			p.position.z + (sin_r * lx + cos_r * lz) * p.scale,
		}
		obj.rotation_y = p.rotation_y + obj.local_rotation_y
		obj.scale = p.scale * obj.local_scale
	}
}

// Pick the closest object under a screen position. Returns index or -1.
scene_pick :: proc(scene: ^Scene, screen_pos: rl.Vector2, camera: rl.Camera3D) -> int {
	ray := rl.GetScreenToWorldRay(screen_pos, camera)

	closest_idx := -1
	closest_dist := max(f32)

	for i in 0 ..< len(scene.objects) {
		obj := &scene.objects[i]
		if !obj.loaded do continue
		r := obj.bounds_radius * obj.scale
		if r <= 0 do continue

		collision := rl.GetRayCollisionSphere(ray, obj.position, r)
		if collision.hit && collision.distance < closest_dist {
			closest_dist = collision.distance
			closest_idx = i
		}
	}

	return closest_idx
}
