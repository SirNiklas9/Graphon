package main

// Block character pixel font — letters are small Grafel patterns
// Each glyph is 3 wide x 5 tall (compact monospace)
// 1 = filled, 0 = empty

GLYPH_W :: 3
GLYPH_H :: 5
GLYPH_SPACING :: 1 // 1 cell gap between characters

Glyph :: [GLYPH_H][GLYPH_W]u8

// Draw text using block character pixel font
draw_text :: proc(grid: ^Grid, x, y: int, text: string, color: [4]u8, bg: [4]u8 = {0, 0, 0, 0}, scale: int = 1) {
	cursor_x := x
	s := max(scale, 1)

	for ch in text {
		if ch == ' ' {
			cursor_x += (GLYPH_W + GLYPH_SPACING) * s
			continue
		}

		glyph, ok := get_glyph(ch)
		if !ok {
			cursor_x += (GLYPH_W + GLYPH_SPACING) * s
			continue
		}

		for gy in 0 ..< GLYPH_H {
			for gx in 0 ..< GLYPH_W {
				if glyph[gy][gx] == 1 {
					for sy in 0 ..< s {
						for sx in 0 ..< s {
							plot_grafel(grid, cursor_x + gx * s + sx, y + gy * s + sy, color, 1.0)
						}
					}
				} else if bg[3] > 0 {
					for sy in 0 ..< s {
						for sx in 0 ..< s {
							plot_grafel(grid, cursor_x + gx * s + sx, y + gy * s + sy, bg, 1.0)
						}
					}
				}
			}
		}

		cursor_x += (GLYPH_W + GLYPH_SPACING) * s
	}
}

// Measure text width in cells
measure_text :: proc(text: string, scale: int = 1) -> int {
	s := max(scale, 1)
	if len(text) == 0 do return 0
	return len(text) * (GLYPH_W + GLYPH_SPACING) * s - GLYPH_SPACING * s
}

get_glyph :: proc(ch: rune) -> (Glyph, bool) {
	switch ch {
	case 'A', 'a': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
		{1, 0, 1},
		{1, 0, 1},
	}, true
	case 'B', 'b': return {
		{1, 1, 0},
		{1, 0, 1},
		{1, 1, 0},
		{1, 0, 1},
		{1, 1, 0},
	}, true
	case 'C', 'c': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 0, 0},
		{1, 0, 0},
		{1, 1, 1},
	}, true
	case 'D', 'd': return {
		{1, 1, 0},
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 0},
	}, true
	case 'E', 'e': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 1, 0},
		{1, 0, 0},
		{1, 1, 1},
	}, true
	case 'F', 'f': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 1, 0},
		{1, 0, 0},
		{1, 0, 0},
	}, true
	case 'G', 'g': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case 'H', 'h': return {
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
		{1, 0, 1},
		{1, 0, 1},
	}, true
	case 'I', 'i': return {
		{1, 1, 1},
		{0, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
		{1, 1, 1},
	}, true
	case 'J', 'j': return {
		{0, 0, 1},
		{0, 0, 1},
		{0, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case 'K', 'k': return {
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 0},
		{1, 0, 1},
		{1, 0, 1},
	}, true
	case 'L', 'l': return {
		{1, 0, 0},
		{1, 0, 0},
		{1, 0, 0},
		{1, 0, 0},
		{1, 1, 1},
	}, true
	case 'M', 'm': return {
		{1, 0, 1},
		{1, 1, 1},
		{1, 1, 1},
		{1, 0, 1},
		{1, 0, 1},
	}, true
	case 'N', 'n': return {
		{1, 0, 1},
		{1, 1, 1},
		{1, 1, 1},
		{1, 1, 1},
		{1, 0, 1},
	}, true
	case 'O', 'o': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case 'P', 'p': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
		{1, 0, 0},
		{1, 0, 0},
	}, true
	case 'Q', 'q': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
		{0, 0, 1},
	}, true
	case 'R', 'r': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 0},
		{1, 0, 1},
		{1, 0, 1},
	}, true
	case 'S', 's': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 1, 1},
		{0, 0, 1},
		{1, 1, 1},
	}, true
	case 'T', 't': return {
		{1, 1, 1},
		{0, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
	}, true
	case 'U', 'u': return {
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case 'V', 'v': return {
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{0, 1, 0},
	}, true
	case 'W', 'w': return {
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
		{1, 1, 1},
		{1, 0, 1},
	}, true
	case 'X', 'x': return {
		{1, 0, 1},
		{1, 0, 1},
		{0, 1, 0},
		{1, 0, 1},
		{1, 0, 1},
	}, true
	case 'Y', 'y': return {
		{1, 0, 1},
		{1, 0, 1},
		{0, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
	}, true
	case 'Z', 'z': return {
		{1, 1, 1},
		{0, 0, 1},
		{0, 1, 0},
		{1, 0, 0},
		{1, 1, 1},
	}, true
	case '0': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case '1': return {
		{0, 1, 0},
		{1, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
		{1, 1, 1},
	}, true
	case '2': return {
		{1, 1, 1},
		{0, 0, 1},
		{1, 1, 1},
		{1, 0, 0},
		{1, 1, 1},
	}, true
	case '3': return {
		{1, 1, 1},
		{0, 0, 1},
		{1, 1, 1},
		{0, 0, 1},
		{1, 1, 1},
	}, true
	case '4': return {
		{1, 0, 1},
		{1, 0, 1},
		{1, 1, 1},
		{0, 0, 1},
		{0, 0, 1},
	}, true
	case '5': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 1, 1},
		{0, 0, 1},
		{1, 1, 1},
	}, true
	case '6': return {
		{1, 1, 1},
		{1, 0, 0},
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case '7': return {
		{1, 1, 1},
		{0, 0, 1},
		{0, 0, 1},
		{0, 0, 1},
		{0, 0, 1},
	}, true
	case '8': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
	}, true
	case '9': return {
		{1, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
		{0, 0, 1},
		{1, 1, 1},
	}, true
	case '.': return {
		{0, 0, 0},
		{0, 0, 0},
		{0, 0, 0},
		{0, 0, 0},
		{0, 1, 0},
	}, true
	case ',': return {
		{0, 0, 0},
		{0, 0, 0},
		{0, 0, 0},
		{0, 1, 0},
		{1, 0, 0},
	}, true
	case '!': return {
		{0, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
		{0, 0, 0},
		{0, 1, 0},
	}, true
	case '?': return {
		{1, 1, 1},
		{0, 0, 1},
		{0, 1, 0},
		{0, 0, 0},
		{0, 1, 0},
	}, true
	case ':': return {
		{0, 0, 0},
		{0, 1, 0},
		{0, 0, 0},
		{0, 1, 0},
		{0, 0, 0},
	}, true
	case '-': return {
		{0, 0, 0},
		{0, 0, 0},
		{1, 1, 1},
		{0, 0, 0},
		{0, 0, 0},
	}, true
	case '+': return {
		{0, 0, 0},
		{0, 1, 0},
		{1, 1, 1},
		{0, 1, 0},
		{0, 0, 0},
	}, true
	case '/': return {
		{0, 0, 1},
		{0, 0, 1},
		{0, 1, 0},
		{1, 0, 0},
		{1, 0, 0},
	}, true
	case '(': return {
		{0, 1, 0},
		{1, 0, 0},
		{1, 0, 0},
		{1, 0, 0},
		{0, 1, 0},
	}, true
	case ')': return {
		{0, 1, 0},
		{0, 0, 1},
		{0, 0, 1},
		{0, 0, 1},
		{0, 1, 0},
	}, true
	}
	return {}, false
}
