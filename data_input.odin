package main

import "core:net"
import "core:strings"
import "core:strconv"
import "core:fmt"
import rl "vendor:raylib"

DataInput :: struct {
	socket: net.UDP_Socket,
	port:   int,
	buffer: [4096]u8,
	active: bool,
}

data_input_create :: proc(port: int = 9999) -> DataInput {
	di := DataInput{
		port = port,
	}

	sock, sock_err := net.create_socket(.IP4, .UDP)
	if sock_err != nil {
		fmt.eprintln("data_input: failed to create socket:", sock_err)
		return di
	}

	// Extract UDP socket from Any_Socket
	udp_sock, is_udp := sock.(net.UDP_Socket)
	if !is_udp {
		fmt.eprintln("data_input: socket is not UDP")
		return di
	}

	bind_err := net.bind(udp_sock, net.Endpoint{
		address = net.IP4_Loopback,
		port    = port,
	})
	if bind_err != nil {
		fmt.eprintln("data_input: failed to bind:", bind_err)
		net.close(udp_sock)
		return di
	}

	net.set_blocking(udp_sock, false)

	di.socket = udp_sock
	di.active = true
	fmt.println("data_input: listening on UDP port", port)
	return di
}

data_input_destroy :: proc(di: ^DataInput) {
	if di.active {
		net.close(di.socket)
		di.active = false
	}
}

data_input_poll :: proc(di: ^DataInput, scene: ^Scene) {
	if !di.active do return

	for {
		bytes_read, _, recv_err := net.recv_udp(di.socket, di.buffer[:])
		if recv_err != nil do break
		if bytes_read <= 0 do break

		msg := strings.trim_right_space(string(di.buffer[:bytes_read]))
		if len(msg) == 0 do continue
		data_input_handle(scene, msg)
	}
}

@(private = "file")
data_input_handle :: proc(scene: ^Scene, line: string) {
	parts := strings.split(line, " ")
	defer delete(parts)
	if len(parts) == 0 do return

	switch parts[0] {
	case "move":
		// move <object_index> <x> <y> <z>
		if len(parts) < 5 do return
		idx, ok1 := strconv.parse_int(parts[1])
		x, ok2 := strconv.parse_f64(parts[2])
		y, ok3 := strconv.parse_f64(parts[3])
		z, ok4 := strconv.parse_f64(parts[4])
		if !ok1 || !ok2 || !ok3 || !ok4 do return
		if idx >= 0 && idx < scene.object_count {
			scene.objects[idx].position = {f32(x), f32(y), f32(z)}
		}

	case "rotate":
		// rotate <object_index> <degrees>
		if len(parts) < 3 do return
		idx, ok1 := strconv.parse_int(parts[1])
		deg, ok2 := strconv.parse_f64(parts[2])
		if !ok1 || !ok2 do return
		if idx >= 0 && idx < scene.object_count {
			scene.objects[idx].rotation_y = f32(deg) * 0.0174533 // degrees to radians
		}

	case "spawn":
		// spawn <model_path> <x> <y> <z> <scale> <r> <g> <b>
		if len(parts) < 9 do return
		model_path := parts[1]
		x, ok1 := strconv.parse_f64(parts[2])
		y, ok2 := strconv.parse_f64(parts[3])
		z, ok3 := strconv.parse_f64(parts[4])
		scale, ok4 := strconv.parse_f64(parts[5])
		ri, ok5 := strconv.parse_int(parts[6])
		gi, ok6 := strconv.parse_int(parts[7])
		bi, ok7 := strconv.parse_int(parts[8])
		if !ok1 || !ok2 || !ok3 || !ok4 || !ok5 || !ok6 || !ok7 do return

		cpath := strings.clone_to_cstring(model_path)
		defer delete(cpath)
		model := rl.LoadModel(cpath)
		mat := material_create({u8(clamp(ri, 0, 255)), u8(clamp(gi, 0, 255)), u8(clamp(bi, 0, 255)), 255})
		scene_add_model(scene, model, {f32(x), f32(y), f32(z)}, mat, f32(scale))

	case "remove":
		// remove <object_index>
		if len(parts) < 2 do return
		idx, ok := strconv.parse_int(parts[1])
		if !ok do return
		scene_remove_object(scene, idx)

	case "light":
		// light <light_index> <x> <y> <z>
		if len(parts) < 5 do return
		idx, ok1 := strconv.parse_int(parts[1])
		x, ok2 := strconv.parse_f64(parts[2])
		y, ok3 := strconv.parse_f64(parts[3])
		z, ok4 := strconv.parse_f64(parts[4])
		if !ok1 || !ok2 || !ok3 || !ok4 do return
		if idx >= 0 && idx < scene.light_count {
			scene.lights[idx].position = {f32(x), f32(y), f32(z)}
		}

	case "camera":
		// camera <x> <y> <z> target:<tx> <ty> <tz>
		if len(parts) < 7 do return
		x, ok1 := strconv.parse_f64(parts[1])
		y, ok2 := strconv.parse_f64(parts[2])
		z, ok3 := strconv.parse_f64(parts[3])
		if !ok1 || !ok2 || !ok3 do return
		// parts[4] is "target:<tx>" — extract value after colon
		target_part := parts[4]
		colon_idx := strings.index(target_part, ":")
		if colon_idx < 0 do return
		tx_str := target_part[colon_idx + 1:]
		tx, ok4 := strconv.parse_f64(tx_str)
		ty, ok5 := strconv.parse_f64(parts[5])
		tz, ok6 := strconv.parse_f64(parts[6])
		if !ok4 || !ok5 || !ok6 do return
		scene.camera.rl_cam.position = {f32(x), f32(y), f32(z)}
		scene.camera.rl_cam.target = {f32(tx), f32(ty), f32(tz)}
	}
}
