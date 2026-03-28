package main

import "core:math"

// Plot a single Grafel at grid position using the solver
plot_grafel :: proc(grid: ^Grid, col, row: int, color: [4]u8, opacity: f32 = 1.0, blend: BlendMode = .Normal) {
	if col < 0 || col >= grid.cols || row < 0 || row >= grid.rows do return
	existing := grid.cells[row * grid.cols + col]
	grid.cells[row * grid.cols + col] = solve_cell(color, opacity, existing.bg, blend)
}

// Clear entire grid to a solid background color
clear_grid :: proc(grid: ^Grid, bg: [4]u8) {
	for i in 0 ..< len(grid.cells) {
		grid.cells[i] = Grafel{char = '█', fg = bg, bg = bg}
	}
}

// Fill a rectangle region
fill_rect :: proc(grid: ^Grid, x, y, w, h: int, color: [4]u8, opacity: f32 = 1.0, blend: BlendMode = .Normal) {
	for row in y ..< y + h {
		for col in x ..< x + w {
			plot_grafel(grid, col, row, color, opacity, blend)
		}
	}
}

// Draw a line using Bresenham's algorithm
draw_line :: proc(grid: ^Grid, x1, y1, x2, y2: int, color: [4]u8, opacity: f32 = 1.0) {
	dx := abs(x2 - x1)
	dy := -abs(y2 - y1)
	sx: int = x1 < x2 ? 1 : -1
	sy: int = y1 < y2 ? 1 : -1
	err := dx + dy

	cx, cy := x1, y1
	for {
		plot_grafel(grid, cx, cy, color, opacity)
		if cx == x2 && cy == y2 do break
		e2 := 2 * err
		if e2 >= dy {
			err += dy
			cx += sx
		}
		if e2 <= dx {
			err += dx
			cy += sy
		}
	}
}

// Draw a circle using midpoint algorithm
draw_circle :: proc(grid: ^Grid, cx, cy, r: int, color: [4]u8, opacity: f32 = 1.0) {
	x := r
	y := 0
	err := 1 - r

	for x >= y {
		plot_grafel(grid, cx + x, cy + y, color, opacity)
		plot_grafel(grid, cx - x, cy + y, color, opacity)
		plot_grafel(grid, cx + x, cy - y, color, opacity)
		plot_grafel(grid, cx - x, cy - y, color, opacity)
		plot_grafel(grid, cx + y, cy + x, color, opacity)
		plot_grafel(grid, cx - y, cy + x, color, opacity)
		plot_grafel(grid, cx + y, cy - x, color, opacity)
		plot_grafel(grid, cx - y, cy - x, color, opacity)

		y += 1
		if err < 0 {
			err += 2 * y + 1
		} else {
			x -= 1
			err += 2 * (y - x) + 1
		}
	}
}

// Draw a filled circle
fill_circle :: proc(grid: ^Grid, cx, cy, r: int, color: [4]u8, opacity: f32 = 1.0) {
	for row in cy - r ..= cy + r {
		for col in cx - r ..= cx + r {
			dx := col - cx
			dy := row - cy
			if dx * dx + dy * dy <= r * r {
				plot_grafel(grid, col, row, color, opacity)
			}
		}
	}
}

// Draw a rectangle outline
draw_rect :: proc(grid: ^Grid, x, y, w, h: int, color: [4]u8, opacity: f32 = 1.0) {
	draw_line(grid, x, y, x + w - 1, y, color, opacity)             // top
	draw_line(grid, x, y + h - 1, x + w - 1, y + h - 1, color, opacity) // bottom
	draw_line(grid, x, y, x, y + h - 1, color, opacity)             // left
	draw_line(grid, x + w - 1, y, x + w - 1, y + h - 1, color, opacity) // right
}
