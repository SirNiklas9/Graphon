package main

import rl "vendor:raylib"

// Mouse state tracked in grid coordinates
Mouse :: struct {
	col:       int,
	row:       int,
	prev_col:  int,
	prev_row:  int,
	pixel_x:   f32,
	pixel_y:   f32,
	in_bounds: bool,
	left:      bool,
	right:     bool,
	middle:    bool,
	left_pressed:  bool,
	right_pressed: bool,
	left_released: bool,
}

mouse_update :: proc(mouse: ^Mouse, grid: ^Grid) {
	mouse.prev_col = mouse.col
	mouse.prev_row = mouse.row

	pos := rl.GetMousePosition()
	mouse.pixel_x = pos.x
	mouse.pixel_y = pos.y

	if grid.cell_w > 0 && grid.cell_h > 0 && len(grid.cells) > 0 {
		mouse.col = int(pos.x / grid.cell_w)
		mouse.row = int(pos.y / grid.cell_h)
		mouse.col = clamp(mouse.col, 0, max(grid.cols - 1, 0))
		mouse.row = clamp(mouse.row, 0, max(grid.rows - 1, 0))
		mouse.in_bounds = mouse.col >= 0 && mouse.col < grid.cols && mouse.row >= 0 && mouse.row < grid.rows
	} else {
		mouse.in_bounds = false
	}

	mouse.left = rl.IsMouseButtonDown(.LEFT)
	mouse.right = rl.IsMouseButtonDown(.RIGHT)
	mouse.middle = rl.IsMouseButtonDown(.MIDDLE)
	mouse.left_pressed = rl.IsMouseButtonPressed(.LEFT)
	mouse.right_pressed = rl.IsMouseButtonPressed(.RIGHT)
	mouse.left_released = rl.IsMouseButtonReleased(.LEFT)
}

// Draw a cursor Grafel at the mouse position
draw_cursor :: proc(grid: ^Grid, mouse: ^Mouse, color: [4]u8 = {255, 255, 255, 255}) {
	if !mouse.in_bounds do return
	if mouse.col >= grid.cols || mouse.row >= grid.rows do return
	idx := mouse.row * grid.cols + mouse.col
	if idx >= len(grid.cells) do return
	existing := grid.cells[idx]
	grid.cells[idx] = Grafel{
		char = '█',
		fg   = {255 - existing.fg[0], 255 - existing.fg[1], 255 - existing.fg[2], 255},
		bg   = {255 - existing.bg[0], 255 - existing.bg[1], 255 - existing.bg[2], 255},
	}
}
