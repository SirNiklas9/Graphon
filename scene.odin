package main

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:unicode/utf8"

// Load a .grf scene file → Grid
load_scene :: proc(path: string) -> (grid: Grid, ok: bool) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil do return {}, false
	defer delete(data)

	content := string(data)
	lines := strings.split(content, "\n")
	defer delete(lines)

	bg_color := [4]u8{0, 0, 0, 255}
	fg_color := [4]u8{255, 255, 255, 255}
	content_lines: [dynamic]string
	defer delete(content_lines)

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 do continue

		if trimmed[0] == '#' {
			meta := strings.trim_space(trimmed[1:])
			if strings.has_prefix(meta, "bg:") {
				bg_color = parse_color(strings.trim_space(meta[3:]))
			}
		} else {
			append(&content_lines, trimmed)
		}
	}

	if len(content_lines) == 0 do return {}, false

	max_cols := 0
	for line in content_lines {
		cols := utf8.rune_count_in_string(line)
		if cols > max_cols do max_cols = cols
	}
	rows := len(content_lines)

	grid.cols = max_cols
	grid.rows = rows
	grid.cell_w = 20
	grid.cell_h = 20
	grid.font_size = 20
	grid.cells = make([]Grafel, max_cols * rows)

	for i in 0 ..< len(grid.cells) {
		grid.cells[i] = Grafel{char = '█', fg = bg_color, bg = bg_color}
	}

	for row in 0 ..< rows {
		col := 0
		for ch in content_lines[row] {
			if col >= max_cols do break
			grid.cells[row * max_cols + col] = Grafel{
				char = ch,
				fg   = fg_color,
				bg   = bg_color,
			}
			col += 1
		}
	}

	return grid, true
}

// Save a Grid as a .grf scene file
save_scene :: proc(grid: ^Grid, path: string) -> bool {
	buf: strings.Builder
	strings.builder_init(&buf)
	defer strings.builder_destroy(&buf)

	fmt.sbprintf(&buf, "# width: %d\n", grid.cols)
	fmt.sbprintf(&buf, "# height: %d\n", grid.rows)

	for row in 0 ..< grid.rows {
		for col in 0 ..< grid.cols {
			g := grid.cells[row * grid.cols + col]
			encoded, n := utf8.encode_rune(g.char)
			strings.write_bytes(&buf, encoded[:n])
		}
		strings.write_byte(&buf, '\n')
	}

	write_err := os.write_entire_file_from_bytes(path, buf.buf[:])
	return write_err == nil
}

// Parse "r,g,b,a" string to color
parse_color :: proc(s: string) -> [4]u8 {
	parts := strings.split(s, ",")
	defer delete(parts)

	result := [4]u8{255, 255, 255, 255}
	for i in 0 ..< min(len(parts), 4) {
		val, parse_ok := strconv.parse_int(strings.trim_space(parts[i]))
		if parse_ok {
			result[i] = u8(clamp(val, 0, 255))
		}
	}
	return result
}
