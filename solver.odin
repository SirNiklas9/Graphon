package main

import rl "vendor:raylib"

// Blend modes for compositing
BlendMode :: enum {
	Normal,    // replace
	Alpha,     // blend by opacity
	Additive,  // add to existing (glow, light)
	Multiply,  // multiply with existing (shadows)
}

// Map an opacity value (0.0–1.0) to the nearest density character
opacity_to_char :: proc(opacity: f32) -> rune {
	if opacity >= 0.875 do return '█'
	if opacity >= 0.625 do return '▓'
	if opacity >= 0.375 do return '▒'
	if opacity >= 0.125 do return '░'
	return '█' // 0.0 — full block but fg=bg (invisible)
}

// Map a density character back to its opacity value
char_to_opacity :: proc(ch: rune) -> f32 {
	switch ch {
	case '█': return 1.0
	case '▓': return 0.75
	case '▒': return 0.50
	case '░': return 0.25
	}
	return 1.0
}

// Solve a cell: given a color, opacity, and existing background, produce a Grafel
solve_cell :: proc(fg_color: [4]u8, opacity: f32, bg_color: [4]u8, blend: BlendMode = .Normal) -> Grafel {
	if opacity <= 0.0 {
		return Grafel{char = '█', fg = bg_color, bg = bg_color}
	}

	blended_fg: [4]u8
	rl_fg := transmute(rl.Color)fg_color
	rl_bg := transmute(rl.Color)bg_color

	switch blend {
	case .Normal:
		blended_fg = fg_color
	case .Alpha:
		blended_fg = transmute([4]u8)rl.ColorLerp(rl_bg, rl_fg, opacity)
	case .Additive:
		blended_fg = {
			clamp_u8(u16(bg_color[0]) + u16(f32(fg_color[0]) * opacity)),
			clamp_u8(u16(bg_color[1]) + u16(f32(fg_color[1]) * opacity)),
			clamp_u8(u16(bg_color[2]) + u16(f32(fg_color[2]) * opacity)),
			255,
		}
	case .Multiply:
		blended_fg = {
			u8((u16(bg_color[0]) * u16(fg_color[0])) / 255),
			u8((u16(bg_color[1]) * u16(fg_color[1])) / 255),
			u8((u16(bg_color[2]) * u16(fg_color[2])) / 255),
			255,
		}
	}

	return Grafel{
		char = opacity_to_char(opacity),
		fg   = blended_fg,
		bg   = bg_color,
	}
}

// Blend two Grafels together (top onto bottom)
blend_grafel :: proc(bottom, top: Grafel, blend: BlendMode = .Alpha) -> Grafel {
	top_opacity := char_to_opacity(top.char)
	if top.fg == top.bg do top_opacity = 0.0
	return solve_cell(top.fg, top_opacity, bottom.fg, blend)
}

clamp_u8 :: proc(v: u16) -> u8 {
	return v >= 255 ? 255 : u8(v)
}
