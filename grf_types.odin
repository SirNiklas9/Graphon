package main

import rl "vendor:raylib"

// .grf file types
GrfType :: enum {
	Object,  // 3D model reference + material
	Grafel,  // 2D pixel art (inline block characters)
	Voxel,   // 3D voxel geometry (layered text slices)
	Scene,   // Composition of objects, lights, volumes, camera
}

// Parsed .grf file
GrfFile :: struct {
	type:     GrfType,
	path:     string,       // source file path (for relative includes)
	data:     GrfData,
}

GrfData :: union {
	GrfObject,
	GrfGrafel,
	GrfVoxel,
	GrfScene,
}

// Object — references a model file with material properties
GrfObject :: struct {
	model_path:   string,
	sprite_path:  string,     // alternative: reference a .grf grafel or .png
	normal_path:  string,     // normal map texture
	color:        rl.Color,
	specular:     f32,
	roughness:    f32,
	billboard:    bool,
}

// Grafel — 2D pixel art defined inline with block characters
GrfGrafel :: struct {
	width:  int,
	height: int,
	rows:   [dynamic]GrfGrafelRow,
}

GrfGrafelRow :: struct {
	text: string,
	fg:   rl.Color,
	bg:   rl.Color,
}

// Voxel — 3D geometry as layered 2D text slices
GrfVoxel :: struct {
	palette: map[rune]rl.Color, // character → color, '.' = air
	layers:  [dynamic]GrfVoxelLayer,
	size_x:  int,               // max width across all layers
	size_y:  int,               // number of layers
	size_z:  int,               // max depth (rows per layer)
}

GrfVoxelLayer :: struct {
	index: int,
	rows:  [dynamic]string,
}

// Scene — composes everything
GrfScene :: struct {
	camera_pos:    rl.Vector3,
	camera_target: rl.Vector3,
	includes:      [dynamic]GrfSceneInclude,
	lights:        [dynamic]GrfSceneLight,
	volumes:       [dynamic]GrfSceneVolume,
	fog_color:     rl.Vector3,
	fog_start:     f32,
	fog_end:       f32,
	fog_enabled:   bool,
	ambient:       rl.Vector3,
}

GrfSceneInclude :: struct {
	path:     string,
	position: rl.Vector3,
	scale:    f32,
	rotate:   f32,        // Y-axis rotation in degrees
}

GrfSceneLight :: struct {
	type:     LightType,
	position: rl.Vector3,
	target:   rl.Vector3,
	color:    rl.Vector3,
}

GrfSceneVolume :: struct {
	min_pos: rl.Vector3,
	max_pos: rl.Vector3,
	color:   rl.Vector3,
	density: f32,
}

// Cleanup
grf_file_destroy :: proc(grf: ^GrfFile) {
	switch &d in grf.data {
	case GrfObject:
		// strings are from the parser, freed with the file content
	case GrfGrafel:
		delete(d.rows)
	case GrfVoxel:
		delete(d.palette)
		for &layer in d.layers {
			delete(layer.rows)
		}
		delete(d.layers)
	case GrfScene:
		delete(d.includes)
		delete(d.lights)
		delete(d.volumes)
	}
}
