package main

import rl "vendor:raylib"

// Blit a Raylib Image onto the grid as Grafels
// Each pixel maps to one cell. Color becomes fg, opacity from alpha.
blit_image :: proc(grid: ^Grid, x, y: int, image: rl.Image) {
	if image.data == nil do return

	for iy in 0 ..< int(image.height) {
		for ix in 0 ..< int(image.width) {
			color := rl.GetImageColor(image, i32(ix), i32(iy))
			if color.a == 0 do continue

			col := x + ix
			row := y + iy
			if col < 0 || col >= grid.cols || row < 0 || row >= grid.rows do continue

			opacity := f32(color.a) / 255.0
			fg := [4]u8{color.r, color.g, color.b, 255}
			plot_grafel(grid, col, row, fg, opacity)
		}
	}
}

// Blit with scaling — sample the image at a different resolution
blit_image_scaled :: proc(grid: ^Grid, x, y: int, image: rl.Image, scale_w, scale_h: int) {
	if image.data == nil do return
	if scale_w <= 0 || scale_h <= 0 do return

	for gy in 0 ..< scale_h {
		for gx in 0 ..< scale_w {
			// Sample from source image
			sx := i32(f32(gx) / f32(scale_w) * f32(image.width))
			sy := i32(f32(gy) / f32(scale_h) * f32(image.height))
			sx = clamp(sx, 0, image.width - 1)
			sy = clamp(sy, 0, image.height - 1)

			color := rl.GetImageColor(image, sx, sy)
			if color.a == 0 do continue

			col := x + gx
			row := y + gy
			if col < 0 || col >= grid.cols || row < 0 || row >= grid.rows do continue

			opacity := f32(color.a) / 255.0
			fg := [4]u8{color.r, color.g, color.b, 255}
			plot_grafel(grid, col, row, fg, opacity)
		}
	}
}
