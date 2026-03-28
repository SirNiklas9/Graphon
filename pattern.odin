package main

// Named reusable Grafel patterns — define once, stamp anywhere
Pattern :: struct {
	width:  int,
	height: int,
	cells:  []Grafel,
}

PatternLib :: struct {
	patterns: map[string]Pattern,
}

pattern_lib_create :: proc() -> PatternLib {
	return PatternLib{patterns = make(map[string]Pattern)}
}

pattern_lib_destroy :: proc(lib: ^PatternLib) {
	for _, p in lib.patterns {
		delete(p.cells)
	}
	delete(lib.patterns)
}

// Define a pattern from a string template + color
// '#' = filled, '.' = transparent
pattern_define :: proc(lib: ^PatternLib, name: string, template: []string, color: [4]u8) {
	if len(template) == 0 do return

	h := len(template)
	w := len(template[0])
	cells := make([]Grafel, w * h)

	for row in 0 ..< h {
		line := template[row]
		for col in 0 ..< min(w, len(line)) {
			if line[col] == '#' {
				cells[row * w + col] = Grafel{char = '█', fg = color, bg = {0, 0, 0, 0}}
			}
			// '.' or anything else = transparent (zero-initialized, bg alpha = 0)
		}
	}

	lib.patterns[name] = Pattern{width = w, height = h, cells = cells}
}

// Stamp a pattern onto the grid at position
draw_pattern :: proc(grid: ^Grid, lib: ^PatternLib, x, y: int, name: string, color_override: [4]u8 = {0, 0, 0, 0}) {
	p, ok := lib.patterns[name]
	if !ok do return

	for row in 0 ..< p.height {
		for col in 0 ..< p.width {
			g := p.cells[row * p.width + col]
			if g.bg[3] == 0 && g.fg[3] == 0 do continue // transparent

			fg := color_override[3] > 0 ? color_override : g.fg
			plot_grafel(grid, x + col, y + row, fg, 1.0)
		}
	}
}
