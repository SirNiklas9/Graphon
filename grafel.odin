package main

import rl "vendor:raylib"
import "core:math"

// The Grafel primitive — grapheme element
// A single cell: Unicode block character (coverage shape) + foreground RGBA + background RGBA
Grafel :: struct {
	char: rune,
	fg:   [4]u8,
	bg:   [4]u8,
}

// All 32 Unicode block codepoints used by Graphon
ALL_CODEPOINTS :: [32]rune{
	// Density (4)
	'█', '▓', '▒', '░',
	// Half (4)
	'▀', '▄', '▌', '▐',
	// Fractional (14)
	'▁', '▂', '▃', '▅', '▆', '▇',
	'▉', '▊', '▋', '▍', '▎', '▏',
	'▔', '▕',
	// Quarter (10)
	'▖', '▗', '▘', '▝', '▙', '▚',
	'▛', '▜', '▞', '▟',
}

// The Grafel buffer — flat framebuffer of cells
Grid :: struct {
	cells:     []Grafel,
	cols:      int,
	rows:      int,
	cell_w:    f32,
	cell_h:    f32,
	font_size: i32,
}

grid_init :: proc(grid: ^Grid, screen_w, screen_h: i32, font: rl.Font, font_size: i32) {
	grid.font_size = font_size

	// Measure cell dimensions from the monospace font
	measured := rl.MeasureTextEx(font, "W", f32(font_size), 0)
	grid.cell_w = measured.x
	grid.cell_h = measured.y

	// Overflow by +1 to prevent black bars at edges
	grid.cols = int(math.ceil(f32(screen_w) / grid.cell_w)) + 1
	grid.rows = int(math.ceil(f32(screen_h) / grid.cell_h)) + 1

	grid.cells = make([]Grafel, grid.cols * grid.rows)
}

grid_destroy :: proc(grid: ^Grid) {
	delete(grid.cells)
}

grid_resize :: proc(grid: ^Grid, screen_w, screen_h: i32, font: rl.Font, font_size: i32) {
	delete(grid.cells)
	grid_init(grid, screen_w, screen_h, font, font_size)
}

grid_set :: proc(grid: ^Grid, col, row: int, g: Grafel) {
	if col >= 0 && col < grid.cols && row >= 0 && row < grid.rows {
		grid.cells[row * grid.cols + col] = g
	}
}

grid_get :: proc(grid: ^Grid, col, row: int) -> Grafel {
	if col >= 0 && col < grid.cols && row >= 0 && row < grid.rows {
		return grid.cells[row * grid.cols + col]
	}
	return Grafel{}
}
