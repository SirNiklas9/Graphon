package main

// Named color palette — runtime swappable for instant theme changes
Palette :: struct {
	colors: map[string][4]u8,
}

palette_create :: proc() -> Palette {
	return Palette{colors = make(map[string][4]u8)}
}

palette_destroy :: proc(p: ^Palette) {
	delete(p.colors)
}

palette_set :: proc(p: ^Palette, name: string, color: [4]u8) {
	p.colors[name] = color
}

palette_get :: proc(p: ^Palette, name: string) -> [4]u8 {
	if color, ok := p.colors[name]; ok {
		return color
	}
	return {255, 0, 255, 255} // magenta = missing color
}

// Load a default palette with common colors
palette_default :: proc(p: ^Palette) {
	palette_set(p, "black",   {0, 0, 0, 255})
	palette_set(p, "white",   {255, 255, 255, 255})
	palette_set(p, "red",     {255, 0, 0, 255})
	palette_set(p, "green",   {0, 255, 0, 255})
	palette_set(p, "blue",    {0, 0, 255, 255})
	palette_set(p, "yellow",  {255, 255, 0, 255})
	palette_set(p, "cyan",    {0, 255, 255, 255})
	palette_set(p, "magenta", {255, 0, 255, 255})
	palette_set(p, "orange",  {255, 165, 0, 255})
	palette_set(p, "gray",    {128, 128, 128, 255})
	palette_set(p, "dark",    {32, 32, 32, 255})
}
