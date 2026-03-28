package main

import rl "vendor:raylib"
import "core:math"

render_grid :: proc(grid: ^Grid, font: rl.Font) {
	full_only := grid.fidelity == .FULL_ONLY
	rect_w := math.ceil(grid.cell_w) + 1
	rect_h := math.ceil(grid.cell_h) + 1

	for row in 0 ..< grid.rows {
		for col in 0 ..< grid.cols {
			g := grid.cells[row * grid.cols + col]

			x := f32(col) * grid.cell_w
			y := f32(row) * grid.cell_h

			// Background rect — ceil +1px to prevent seam gaps
			rl.DrawRectangleRec(
				{x, y, rect_w, rect_h},
				transmute(rl.Color)g.bg,
			)

			// At FULL_ONLY fidelity, skip text — just draw colored rects
			if full_only {
				rl.DrawRectangleRec(
					{x, y, rect_w, rect_h},
					transmute(rl.Color)g.fg,
				)
				continue
			}

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
