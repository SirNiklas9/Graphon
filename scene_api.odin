package main

import rl "vendor:raylib"

MAX_SCENE_OBJECTS  :: 256
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
	// Objects
	objects:      [MAX_SCENE_OBJECTS]Scene3DObject,
	object_count: int,

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
	if scene.object_count >= MAX_SCENE_OBJECTS do return -1
	idx := scene.object_count

	// Apply diffuse texture to model materials if provided
	if mat.diffuse_tex.id != 0 {
		for mi in 0 ..< model.materialCount {
			model.materials[mi].maps[rl.MaterialMapIndex.ALBEDO].texture = mat.diffuse_tex
		}
	}

	scene.objects[idx] = Scene3DObject{
		model        = model,
		loaded       = model.meshCount > 0,
		position     = position,
		scale        = scale,
		tint         = mat.diffuse_color != {} ? mat.diffuse_color : rl.WHITE,
		normal_map   = mat.normal_map,
		specular     = mat.specular,
		roughness    = mat.roughness,
	}
	scene.object_count += 1
	return idx
}

// Add a primitive cube to the scene
scene_add_cube :: proc(scene: ^Scene, position: rl.Vector3, size: rl.Vector3, color: rl.Color) -> int {
	if scene.object_count >= MAX_SCENE_OBJECTS do return -1
	idx := scene.object_count
	scene.objects[idx] = Scene3DObject{
		loaded       = true, // primitive, no model needed
		position     = position,
		scale        = 1.0,
		tint         = color,
	}
	scene.object_count += 1
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
	if idx < 0 || idx >= scene.object_count do return
	// Shift remaining objects down
	for i in idx ..< scene.object_count - 1 {
		scene.objects[i] = scene.objects[i + 1]
	}
	scene.object_count -= 1
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
