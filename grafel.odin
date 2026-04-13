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

// Fidelity levels — which character subsets are available at a given cell size
Fidelity :: enum {
	FULL_ONLY,    // cell < 6px  — just colored rects, no text draw
	DENSITY,      // cell >= 6px — █ ▓ ▒ ░
	HALF,         // cell >= 10px — + ▀ ▄ ▌ ▐
	FRACTIONAL,   // cell >= 16px — + ▁▂▃▅▆▇ ▉▊▋▍▎▏ ▔▕
	ALL,          // cell >= 20px — + ▖▗▘▝▙▚▛▜▞▟
}

// Character subsets by fidelity tier
DENSITY_CHARS    :: [4]rune{'█', '▓', '▒', '░'}
HALF_CHARS       :: [4]rune{'▀', '▄', '▌', '▐'}
FRACTIONAL_CHARS :: [14]rune{'▁', '▂', '▃', '▅', '▆', '▇', '▉', '▊', '▋', '▍', '▎', '▏', '▔', '▕'}
QUARTER_CHARS    :: [10]rune{'▖', '▗', '▘', '▝', '▙', '▚', '▛', '▜', '▞', '▟'}

fidelity_from_cell_size :: proc(cell_size: f32) -> Fidelity {
	if cell_size >= 20 do return .ALL
	if cell_size >= 16 do return .FRACTIONAL
	if cell_size >= 10 do return .HALF
	if cell_size >= 6  do return .DENSITY
	return .FULL_ONLY
}

// The Grafel buffer — flat framebuffer of cells
Grid :: struct {
	cells:     []Grafel,
	cols:      int,
	rows:      int,
	cell_w:    f32,
	cell_h:    f32,
	font_size: i32,
	fidelity:  Fidelity,
	forced_fidelity: bool,
}

grid_init :: proc(grid: ^Grid, screen_w, screen_h: i32, font: rl.Font, font_size: i32) {
	grid.font_size = font_size

	// Measure cell dimensions from a loaded block character
	measured := rl.MeasureTextEx(font, "█", f32(font_size), 0)
	grid.cell_w = max(measured.x, 1)
	grid.cell_h = max(measured.y, 1)

	// Overflow by +1 to prevent black bars at edges
	grid.cols = int(math.ceil(f32(screen_w) / grid.cell_w)) + 1
	grid.rows = int(math.ceil(f32(screen_h) / grid.cell_h)) + 1

	grid.cols = max(grid.cols, 1)
	grid.rows = max(grid.rows, 1)

	grid.cells = make([]Grafel, grid.cols * grid.rows)

	if !grid.forced_fidelity {
		grid.fidelity = fidelity_from_cell_size(min(grid.cell_w, grid.cell_h))
	}
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

// Convert a GrfGrafel (2D pixel art) into a billboarded 3D model.
// Rasterizes each row's characters as colored rectangles into an RGBA texture,
// maps it onto a plane mesh, returns a Model ready for scene_add_model.
grafel_to_billboard :: proc(g: ^GrfGrafel) -> (rl.Model, bool) {
	if len(g.rows) == 0 do return {}, false

	// Determine pixel dimensions: 8px per cell
	cell_px :: 8
	w := g.width > 0 ? g.width : 16
	h := g.height > 0 ? g.height : len(g.rows)
	img_w := i32(w * cell_px)
	img_h := i32(h * cell_px)

	// Create image and fill with transparent black
	img := rl.GenImageColor(img_w, img_h, {0, 0, 0, 0})

	// Draw each row
	for ri in 0 ..< min(len(g.rows), h) {
		row := &g.rows[ri]
		// Each character in the row text = one cell
		ci := 0
		for ch in row.text {
			if ci >= w do break
			// Draw cell as a colored rectangle
			// Full block (█) = fg only, space = bg only, others = fg (simplified)
			color := ch == ' ' ? row.bg : row.fg

			rect := rl.Rectangle{
				f32(ci * cell_px), f32(ri * cell_px),
				f32(cell_px), f32(cell_px),
			}
			rl.ImageDrawRectangleRec(&img, rect, color)
			ci += 1
		}
	}

	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)

	if tex.id == 0 do return {}, false

	// Create a plane mesh and assign the texture
	aspect := f32(img_w) / f32(img_h)
	mesh := rl.GenMeshPlane(aspect * 2, 2, 1, 1)
	model := rl.LoadModelFromMesh(mesh)
	model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = tex

	return model, true
}
