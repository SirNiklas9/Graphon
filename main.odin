package main

import rl "vendor:raylib"
import "core:math/rand"
import "core:fmt"
import "core:strings"
import imgui "lib:odin-imgui"
import rlimgui "lib:imgui_impl_raylib"

SCREEN_W     :: 1920
SCREEN_H     :: 1080
INIT_FONT_SZ :: i32(20)
FONT_PATH    :: "assets/JetBrainsMonoNLNerdFont-Regular.ttf"

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Graphon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// ImGui setup
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	rlimgui.init()
	defer rlimgui.shutdown()

	font := load_font(INIT_FONT_SZ)
	defer rl.UnloadFont(font)

	grid: Grid
	grid_init(&grid, SCREEN_W, SCREEN_H, font, INIT_FONT_SZ)
	defer grid_destroy(&grid)

	randomize_grid(&grid)

	for !rl.WindowShouldClose() {
		// Font size adjustment
		if rl.IsKeyPressed(.UP) {
			resize_font(&grid, &font, grid.font_size + 2)
		}
		if rl.IsKeyPressed(.DOWN) {
			resize_font(&grid, &font, grid.font_size - 2)
		}

		// Re-randomize on SPACE
		if rl.IsKeyPressed(.SPACE) {
			randomize_grid(&grid)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Render Grafel grid
		render_grid(&grid, font)

		// ImGui overlay
		rlimgui.begin()

		imgui.SetNextWindowPos({10, 10}, .FirstUseEver)
		imgui.SetNextWindowSize({220, 100}, .FirstUseEver)
		if imgui.Begin("Graphon", nil, {.NoCollapse}) {
			fps_buf: [32]u8
			fps_str := fmt.bprintf(fps_buf[:], "FPS: %d\x00", rl.GetFPS())
			imgui.Text(cstring(raw_data(fps_buf[:])))

			grid_buf: [64]u8
			fmt.bprintf(grid_buf[:], "Grid: %dx%d  Cell: %.0fpx\x00", grid.cols, grid.rows, grid.cell_w)
			imgui.Text(cstring(raw_data(grid_buf[:])))

			font_buf: [32]u8
			fmt.bprintf(font_buf[:], "Font size: %d\x00", grid.font_size)
			imgui.Text(cstring(raw_data(font_buf[:])))
		}
		imgui.End()

		rlimgui.end()
		rl.EndDrawing()
	}
}

load_font :: proc(size: i32) -> rl.Font {
	codepoints := ALL_CODEPOINTS
	font := rl.LoadFontEx(FONT_PATH, size, raw_data(codepoints[:]), i32(len(codepoints)))
	rl.SetTextureFilter(font.texture, .POINT)
	return font
}

resize_font :: proc(grid: ^Grid, font: ^rl.Font, new_size: i32) {
	size := clamp(new_size, 6, 64)
	rl.UnloadFont(font^)
	font^ = load_font(size)
	grid_resize(grid, i32(rl.GetScreenWidth()), i32(rl.GetScreenHeight()), font^, size)
	randomize_grid(grid)
}

randomize_grid :: proc(grid: ^Grid) {
	chars := ALL_CODEPOINTS
	for i in 0 ..< len(grid.cells) {
		grid.cells[i] = Grafel{
			char = chars[rand.uint32() % 32],
			fg   = {u8(rand.uint32() % 256), u8(rand.uint32() % 256), u8(rand.uint32() % 256), 255},
			bg   = {u8(rand.uint32() % 256), u8(rand.uint32() % 256), u8(rand.uint32() % 256), 255},
		}
	}
}
