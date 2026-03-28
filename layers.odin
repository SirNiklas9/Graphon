package main

// 5-layer compositing system
// Background → World → Entity → Effects → UI
// Each layer is its own Grafel buffer, composited top-down

LayerID :: enum {
	Background,
	World,
	Entity,
	Effects,
	UI,
}

LAYER_COUNT :: 5

LayerStack :: struct {
	layers:  [LAYER_COUNT][]Grafel,
	cols:    int,
	rows:    int,
	output:  []Grafel, // composited result
}

layer_stack_create :: proc(cols, rows: int) -> LayerStack {
	ls := LayerStack{cols = cols, rows = rows}
	size := cols * rows
	for i in 0 ..< LAYER_COUNT {
		ls.layers[i] = make([]Grafel, size)
	}
	ls.output = make([]Grafel, size)
	return ls
}

layer_stack_destroy :: proc(ls: ^LayerStack) {
	for i in 0 ..< LAYER_COUNT {
		delete(ls.layers[i])
	}
	delete(ls.output)
}

layer_stack_resize :: proc(ls: ^LayerStack, cols, rows: int) {
	layer_stack_destroy(ls)
	ls^ = layer_stack_create(cols, rows)
}

// Clear a single layer (transparent = alpha 0)
layer_clear :: proc(ls: ^LayerStack, id: LayerID, bg: [4]u8 = {0, 0, 0, 0}) {
	for i in 0 ..< len(ls.layers[id]) {
		ls.layers[id][i] = Grafel{char = '█', fg = bg, bg = bg}
	}
}

// Clear all layers
layer_clear_all :: proc(ls: ^LayerStack) {
	for id in 0 ..< LAYER_COUNT {
		layer_clear(ls, LayerID(id))
	}
}

// Write a Grafel to a specific layer
layer_set :: proc(ls: ^LayerStack, id: LayerID, col, row: int, g: Grafel) {
	if col < 0 || col >= ls.cols || row < 0 || row >= ls.rows do return
	ls.layers[id][row * ls.cols + col] = g
}

// Plot onto a layer using the solver
layer_plot :: proc(ls: ^LayerStack, id: LayerID, col, row: int, color: [4]u8, opacity: f32 = 1.0, blend: BlendMode = .Normal) {
	if col < 0 || col >= ls.cols || row < 0 || row >= ls.rows do return
	idx := row * ls.cols + col
	existing := ls.layers[id][idx]
	ls.layers[id][idx] = solve_cell(color, opacity, existing.bg, blend)
}

// Composite all layers bottom-up into the output buffer
// Background is opaque base, each layer above blends on top
layer_composite :: proc(ls: ^LayerStack) {
	size := ls.cols * ls.rows

	// Start with background layer as base
	for i in 0 ..< size {
		ls.output[i] = ls.layers[LayerID.Background][i]
	}

	// Blend each subsequent layer on top
	for layer_idx in 1 ..< LAYER_COUNT {
		layer := ls.layers[layer_idx]
		for i in 0 ..< size {
			cell := layer[i]
			// Skip fully transparent cells (alpha 0 on both fg and bg)
			if cell.fg[3] == 0 && cell.bg[3] == 0 do continue

			// If cell has visible content, blend it
			opacity := char_to_opacity(cell.char)
			if cell.fg == cell.bg do opacity = 0.0

			if opacity >= 1.0 {
				// Fully opaque — replace
				ls.output[i] = cell
			} else if opacity > 0.0 {
				// Partial — blend fg onto existing
				ls.output[i] = solve_cell(cell.fg, opacity, ls.output[i].fg, .Alpha)
			}
			// opacity 0 with non-zero alpha bg = just the background color
			if opacity <= 0.0 && cell.bg[3] > 0 {
				ls.output[i] = Grafel{char = '█', fg = cell.bg, bg = cell.bg}
			}
		}
	}
}

// Copy the composited output into the main grid for rendering
layer_to_grid :: proc(ls: ^LayerStack, grid: ^Grid) {
	size := min(len(ls.output), len(grid.cells))
	for i in 0 ..< size {
		grid.cells[i] = ls.output[i]
	}
}
