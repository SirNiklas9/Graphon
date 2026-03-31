package main

import "core:os"
import "core:time"

// File polling watcher for .grf hot reload
GrfWatcher :: struct {
	entries:        [dynamic]WatchEntry,
	changed:        [dynamic]string,
	check_interval: f32,
	check_timer:    f32,
}

WatchEntry :: struct {
	path:     string,
	mod_time: time.Time,
}

grf_watcher_create :: proc(interval: f32 = 0.5) -> GrfWatcher {
	return GrfWatcher{
		check_interval = interval,
		check_timer    = interval,
	}
}

grf_watcher_destroy :: proc(w: ^GrfWatcher) {
	delete(w.entries)
	delete(w.changed)
}

grf_watcher_add :: proc(w: ^GrfWatcher, path: string) {
	mod: time.Time
	info, err := os.stat(path, context.allocator)
	if err == nil {
		mod = info.modification_time
		os.file_info_delete(info, context.allocator)
	}
	append(&w.entries, WatchEntry{path = path, mod_time = mod})
}

grf_watcher_update :: proc(w: ^GrfWatcher, dt: f32) -> bool {
	w.check_timer -= dt
	if w.check_timer > 0 {
		return false
	}
	w.check_timer = w.check_interval

	clear(&w.changed)
	any_changed := false

	for &entry in w.entries {
		info, err := os.stat(entry.path, context.allocator)
		if err != nil do continue
		new_mod := info.modification_time
		os.file_info_delete(info, context.allocator)

		if new_mod != entry.mod_time {
			entry.mod_time = new_mod
			append(&w.changed, entry.path)
			any_changed = true
		}
	}

	return any_changed
}

grf_watcher_changed_files :: proc(w: ^GrfWatcher) -> []string {
	return w.changed[:]
}

grf_watcher_clear :: proc(w: ^GrfWatcher) {
	clear(&w.entries)
	clear(&w.changed)
}
