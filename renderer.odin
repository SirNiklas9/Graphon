package main

import rl "vendor:raylib"
import "core:math"

render_grid :: proc(grid: ^Grid, font: rl.Font) {
	for row in 0 ..< grid.rows {
		for col in 0 ..< grid.cols {
			g := grid.cells[row * grid.cols + col]

			x := f32(col) * grid.cell_w
			y := f32(row) * grid.cell_h

			// Background rect — ceil +1px to prevent seam gaps
			rl.DrawRectangleRec(
				{x, y, math.ceil(grid.cell_w) + 1, math.ceil(grid.cell_h) + 1},
				transmute(rl.Color)g.bg,
			)

			// Foreground character
			rl.DrawTextCodepoint(
				font,
				g.char,
				{x, y},
				f32(grid.font_size),
				transmute(rl.Color)g.fg,
			)
		}
	}
}
