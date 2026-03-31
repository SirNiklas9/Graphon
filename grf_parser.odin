package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Helpers

grf_parse_vec3 :: proc(s: string) -> rl.Vector3 {
	parts := strings.split(s, ",")
	defer delete(parts)
	if len(parts) != 3 do return {}
	x := grf_parse_float(parts[0])
	y := grf_parse_float(parts[1])
	z := grf_parse_float(parts[2])
	return {x, y, z}
}

grf_parse_color :: proc(s: string) -> rl.Color {
	parts := strings.split(s, ",")
	defer delete(parts)
	if len(parts) != 3 do return rl.WHITE
	r, r_ok := strconv.parse_int(strings.trim_space(parts[0]))
	g, g_ok := strconv.parse_int(strings.trim_space(parts[1]))
	b, b_ok := strconv.parse_int(strings.trim_space(parts[2]))
	if !r_ok || !g_ok || !b_ok do return rl.WHITE
	return {u8(clamp(r, 0, 255)), u8(clamp(g, 0, 255)), u8(clamp(b, 0, 255)), 255}
}

grf_grf_parse_color_vec3 :: proc(s: string) -> rl.Vector3 {
	parts := strings.split(s, ",")
	defer delete(parts)
	if len(parts) != 3 do return {1, 1, 1}
	x := grf_parse_float(parts[0])
	y := grf_parse_float(parts[1])
	z := grf_parse_float(parts[2])
	return {x, y, z}
}

grf_parse_float :: proc(s: string) -> f32 {
	val, ok := strconv.parse_f64(strings.trim_space(s))
	if !ok do return 0
	return f32(val)
}

grf_parse_bool :: proc(s: string) -> bool {
	t := strings.trim_space(s)
	return t == "true" || t == "1" || t == "yes"
}

// State machine states
ParserState :: enum {
	Start,
	Object,
	Grafel_Header,
	Grafel_Content,
	Voxel_Header,
	Voxel_Palette,
	Voxel_Layer,
	Scene,
}

grf_parse :: proc(path: string) -> (GrfFile, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("grf_parse: failed to read file: %s", path)
		return {}, false
	}
	content := string(data)

	result := GrfFile{
		path = path,
	}

	state := ParserState.Start
	grafel_rows_read := 0

	// Temporary state for building data
	obj := GrfObject{
		color     = rl.WHITE,
		specular  = 0.3,
		roughness = 0.5,
	}
	grafel := GrfGrafel{}
	voxel := GrfVoxel{
		palette = make(map[rune]rl.Color),
	}
	scene := GrfScene{
		ambient = {0.1, 0.1, 0.1},
	}
	current_layer_index := -1

	lines := strings.split_lines(content)
	defer delete(lines)

	for line in lines {
		// In voxel layer content, empty lines are significant (end the layer)
		// In all other states, skip empty lines
		trimmed := strings.trim_space(line)

		if state != .Voxel_Layer && state != .Voxel_Palette && state != .Grafel_Content {
			if len(trimmed) == 0 do continue
			if trimmed[0] == '#' do continue
		}

		switch state {
		case .Start:
			key, val := split_kv(trimmed)
			if key != "type" {
				fmt.eprintfln("grf_parse: first meaningful line must be 'type:', got: %s", trimmed)
				return {}, false
			}
			switch val {
			case "object":
				result.type = .Object
				state = .Object
			case "grafel":
				result.type = .Grafel
				state = .Grafel_Header
			case "voxel":
				result.type = .Voxel
				state = .Voxel_Header
			case "scene":
				result.type = .Scene
				state = .Scene
			case:
				fmt.eprintfln("grf_parse: unknown type: %s", val)
				return {}, false
			}

		case .Object:
			if trimmed[0] == '#' do continue
			key, val := split_kv(trimmed)
			switch key {
			case "model":
				obj.model_path = strings.clone(val)
			case "color":
				obj.color = grf_parse_color(val)
			case "specular":
				obj.specular = grf_parse_float(val)
			case "roughness":
				obj.roughness = grf_parse_float(val)
			case "billboard":
				obj.billboard = grf_parse_bool(val)
			case "sprite":
				obj.sprite_path = strings.clone(val)
			case "normal":
				obj.normal_path = strings.clone(val)
			}

		case .Grafel_Header:
			if trimmed[0] == '#' do continue
			key, val := split_kv(trimmed)
			switch key {
			case "width":
				w, w_ok := strconv.parse_int(val)
				if w_ok do grafel.width = w
			case "height":
				h, h_ok := strconv.parse_int(val)
				if h_ok do grafel.height = h
			case:
				// Not a header key — must be start of content
				row, row_ok := parse_grafel_row(trimmed)
				if row_ok {
					append(&grafel.rows, row)
					grafel_rows_read += 1
				}
				state = .Grafel_Content
			}

		case .Grafel_Content:
			if len(trimmed) == 0 do continue
			if trimmed[0] == '#' do continue
			row, row_ok := parse_grafel_row(trimmed)
			if row_ok {
				append(&grafel.rows, row)
				grafel_rows_read += 1
			}

		case .Voxel_Header:
			if len(trimmed) == 0 do continue
			if trimmed[0] == '#' do continue
			if trimmed == "palette:" {
				state = .Voxel_Palette
				continue
			}
			if strings.has_prefix(trimmed, "layer ") {
				idx := parse_layer_index(trimmed)
				current_layer_index = idx
				append(&voxel.layers, GrfVoxelLayer{index = idx})
				state = .Voxel_Layer
				continue
			}

		case .Voxel_Palette:
			if len(trimmed) == 0 do continue
			if trimmed[0] == '#' do continue
			// Check if this is a palette entry (indented with 2 spaces)
			if strings.has_prefix(line, "  ") && !strings.has_prefix(trimmed, "layer ") {
				parse_palette_entry(trimmed, &voxel)
				continue
			}
			// Not indented or is a layer line — transition
			if strings.has_prefix(trimmed, "layer ") {
				idx := parse_layer_index(trimmed)
				current_layer_index = idx
				append(&voxel.layers, GrfVoxelLayer{index = idx})
				state = .Voxel_Layer
				continue
			}

		case .Voxel_Layer:
			// Empty line or non-indented line ends the layer
			if len(trimmed) == 0 do continue
			if trimmed[0] == '#' do continue
			if strings.has_prefix(trimmed, "layer ") {
				// New layer
				idx := parse_layer_index(trimmed)
				current_layer_index = idx
				append(&voxel.layers, GrfVoxelLayer{index = idx})
				continue
			}
			// Content line (indented with 2 spaces or not)
			{
				row_text := strings.clone(trimmed)
				layer_idx := len(voxel.layers) - 1
				if layer_idx >= 0 {
					append(&voxel.layers[layer_idx].rows, row_text)
					// Track max dimensions
					row_width := utf8.rune_count_in_string(trimmed)
					if row_width > voxel.size_x do voxel.size_x = row_width
					row_count := len(voxel.layers[layer_idx].rows)
					if row_count > voxel.size_z do voxel.size_z = row_count
				}
			}

		case .Scene:
			if len(trimmed) == 0 do continue
			if trimmed[0] == '#' do continue
			parse_scene_line(trimmed, &scene)
		}
	}

	// Finalize
	switch state {
	case .Object, .Start:
		if state == .Object {
			result.data = obj
		}
	case .Grafel_Header, .Grafel_Content:
		// Infer dimensions if not set
		if grafel.height == 0 do grafel.height = len(grafel.rows)
		if grafel.width == 0 && len(grafel.rows) > 0 {
			grafel.width = utf8.rune_count_in_string(grafel.rows[0].text)
		}
		result.data = grafel
	case .Voxel_Header, .Voxel_Palette, .Voxel_Layer:
		voxel.size_y = len(voxel.layers)
		result.data = voxel
	case .Scene:
		result.data = scene
	}

	if state == .Start {
		fmt.eprintfln("grf_parse: no type line found in file: %s", path)
		return {}, false
	}

	return result, true
}

// Split "key: value" into key and value, trimming spaces
split_kv :: proc(line: string) -> (key: string, val: string) {
	idx := strings.index(line, ":")
	if idx < 0 do return line, ""
	key = strings.trim_space(line[:idx])
	val = strings.trim_space(line[idx + 1:])
	return
}

// Parse a grafel content row: block characters followed by optional fg:/bg: attributes
parse_grafel_row :: proc(line: string) -> (GrfGrafelRow, bool) {
	row := GrfGrafelRow{
		fg = rl.WHITE,
		bg = rl.BLACK,
	}

	// Find where the block character text ends and attributes begin
	// Block characters are runes >= 0x2580 or space
	text_end := 0
	i := 0
	for i < len(line) {
		r, size := utf8.decode_rune_in_string(line[i:])
		if r == utf8.RUNE_ERROR && size <= 1 do break
		if r >= 0x2580 || r == ' ' {
			text_end = i + size
			i += size
		} else {
			break
		}
	}

	if text_end == 0 {
		// No block characters found — might be spaces only or invalid
		// Try treating the whole thing as text if it starts with space
		return row, false
	}

	row.text = strings.clone(strings.trim_right_space(line[:text_end]))

	// Parse remaining attributes
	rest := strings.trim_space(line[text_end:])
	if len(rest) > 0 {
		tokens := strings.split(rest, " ")
		defer delete(tokens)
		for token in tokens {
			t := strings.trim_space(token)
			if strings.has_prefix(t, "fg:") {
				row.fg = grf_parse_color(t[3:])
			} else if strings.has_prefix(t, "bg:") {
				row.bg = grf_parse_color(t[3:])
			}
		}
	}

	return row, true
}

// Parse "layer N:" and return N
parse_layer_index :: proc(line: string) -> int {
	// line is "layer N:"
	rest := strings.trim_prefix(line, "layer ")
	rest = strings.trim_suffix(rest, ":")
	rest = strings.trim_space(rest)
	idx, ok := strconv.parse_int(rest)
	if !ok do return 0
	return idx
}

// Parse a palette entry like "R: 220,50,40" or ".: air"
parse_palette_entry :: proc(line: string, voxel: ^GrfVoxel) {
	// Format: "X: R,G,B" or "X: air"
	key, val := split_kv(line)
	if len(key) == 0 do return
	r, _ := utf8.decode_rune_in_string(key)
	if val == "air" {
		voxel.palette[r] = {0, 0, 0, 0} // transparent = air
	} else {
		voxel.palette[r] = grf_parse_color(val)
	}
}

// Parse a scene line
parse_scene_line :: proc(line: string, scene: ^GrfScene) {
	key, rest := split_kv(line)
	switch key {
	case "camera":
		parse_camera(rest, scene)
	case "include":
		parse_include(rest, scene)
	case "light":
		parse_light(rest, scene)
	case "volume":
		parse_volume(rest, scene)
	case "fog":
		parse_fog(rest, scene)
	case "ambient":
		scene.ambient = grf_grf_parse_color_vec3(rest)
	}
}

// Parse camera: "-8,6,14 target:0,1,0"
parse_camera :: proc(val: string, scene: ^GrfScene) {
	tokens := strings.split(val, " ")
	defer delete(tokens)
	if len(tokens) >= 1 {
		scene.camera_pos = grf_parse_vec3(tokens[0])
	}
	for token in tokens[1:] {
		t := strings.trim_space(token)
		if strings.has_prefix(t, "target:") {
			scene.camera_target = grf_parse_vec3(t[7:])
		}
	}
}

// Parse include: "sword.grf at 5,1,0 scale:2 rotate:45"
parse_include :: proc(val: string, scene: ^GrfScene) {
	tokens := strings.split(val, " ")
	defer delete(tokens)
	if len(tokens) < 1 do return

	inc := GrfSceneInclude{
		scale = 1.0,
	}
	inc.path = strings.clone(tokens[0])

	i := 1
	for i < len(tokens) {
		t := strings.trim_space(tokens[i])
		if t == "at" && i + 1 < len(tokens) {
			i += 1
			inc.position = grf_parse_vec3(strings.trim_space(tokens[i]))
		} else if strings.has_prefix(t, "scale:") {
			inc.scale = grf_parse_float(t[6:])
		} else if strings.has_prefix(t, "rotate:") {
			inc.rotate = grf_parse_float(t[7:])
		}
		i += 1
	}

	append(&scene.includes, inc)
}

// Parse light: "directional 10,15,5 target:-1,0,-0.5 color:0.9,0.75,0.5"
//          or: "point 8,3,0 color:1.2,0.8,0.3"
parse_light :: proc(val: string, scene: ^GrfScene) {
	tokens := strings.split(val, " ")
	defer delete(tokens)
	if len(tokens) < 2 do return

	light := GrfSceneLight{
		color = {1, 1, 1},
	}

	switch strings.trim_space(tokens[0]) {
	case "directional":
		light.type = .Directional
	case "point":
		light.type = .Point
	}

	light.position = grf_parse_vec3(strings.trim_space(tokens[1]))

	for token in tokens[2:] {
		t := strings.trim_space(token)
		if strings.has_prefix(t, "target:") {
			light.target = grf_parse_vec3(t[7:])
		} else if strings.has_prefix(t, "color:") {
			light.color = grf_grf_parse_color_vec3(t[6:])
		}
	}

	append(&scene.lights, light)
}

// Parse volume: "-20,-1,-20 -5,10,20 color:0.05,0.08,0.2 density:0.3"
parse_volume :: proc(val: string, scene: ^GrfScene) {
	tokens := strings.split(val, " ")
	defer delete(tokens)
	if len(tokens) < 2 do return

	vol := GrfSceneVolume{
		color   = {0.1, 0.1, 0.1},
		density = 0.5,
	}

	vol.min_pos = grf_parse_vec3(strings.trim_space(tokens[0]))
	vol.max_pos = grf_parse_vec3(strings.trim_space(tokens[1]))

	for token in tokens[2:] {
		t := strings.trim_space(token)
		if strings.has_prefix(t, "color:") {
			vol.color = grf_grf_parse_color_vec3(t[6:])
		} else if strings.has_prefix(t, "density:") {
			vol.density = grf_parse_float(t[8:])
		}
	}

	append(&scene.volumes, vol)
}

// Parse fog: "color:0.05,0.05,0.08 start:25 end:60"
parse_fog :: proc(val: string, scene: ^GrfScene) {
	scene.fog_enabled = true
	tokens := strings.split(val, " ")
	defer delete(tokens)
	for token in tokens {
		t := strings.trim_space(token)
		if strings.has_prefix(t, "color:") {
			scene.fog_color = grf_grf_parse_color_vec3(t[6:])
		} else if strings.has_prefix(t, "start:") {
			scene.fog_start = grf_parse_float(t[6:])
		} else if strings.has_prefix(t, "end:") {
			scene.fog_end = grf_parse_float(t[4:])
		}
	}
}
