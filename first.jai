// CHIP-8 emulator
main :: () {
	start_time := current_time_monotonic();
	quit := false;

	the_window = create_window(window_name="Chip-8", width=WINW, height=WINH);
	Simp.set_render_target(the_window);
	Simp.set_shader_for_color();

	chip8_initialize();

	last_cycle_time := current_time_monotonic();

	while !quit {
		Input.update_window_events();
		for Input.events_this_frame {
			if it.type == .QUIT then quit = true;
		}

		now := current_time_monotonic();
		if now - last_cycle_time >= TARGET_CYCLE_TIME {
			chip8_cycle(
				to_float64_seconds(now - last_cycle_time),  // Delta Time
				to_float64_seconds(now - start_time),       // Program time
			);
			last_cycle_time = now;
		}
	}
}

// Memory map
// 0x000-0x1FF - Chip 8 interpreter (contains font set in emu)
// 0x050-0x0A0 - Used for the built in 4x5 pixel font set (0-F)
// 0x200-0xFFF - Program ROM and work RAM

opcode: u16;
memory: [4096] u8;
cpu_registers: [16] u8;
index_register: u16;
program_counter: u16;
stack: Stack(u16, 16);

pixels: [64 * 32] bool;

// Both timers count down at 60Hz
delay_timer: u8;
sound_timer: u8; // When this one reaches 0 it beeps

key_states: [16] u8;

Stack :: struct($T: Type, $N: u64) {
	data: [N] T;
	ptr: u64; 
}

the_window: Window_Type;

chip8_initialize :: () {
	// Setup registers etc;
	
	// Load font
	add_to_memory(0x00FE, 0);
	memcpy(memory.data + 0x50, FONT.data, FONT.count);
	print_memory(memory);
}

chip8_cycle :: (delta_time: float64, program_time: float64) {
	redraw := false;
	// print("% %\n", delta_time, program_time);
	// --- Fetch opcode
	//opcode = memory[program_counter] << 8 | memory[program_counter + 1];

	// --- Decode opcode

	// --- Execute opcode
	
	// --- Update timers
	
	if delay_timer > 0 then delay_timer -= 1;
	if delay_timer == 0 {
		// TODO
	}
	if sound_timer > 0 then sound_timer -= 1;
	if sound_timer == 0 {
		// TODO
	}

	// --- Redraw graphics
	if redraw {
		clear_render_target();

		for pixels {
			if !it continue;
			x := it_index % 64;
			y := it_index / 64;
			draw_pixel(x, y);
		}

		Simp.swap_buffers(the_window);
		redraw = false;
	}
}

draw_pixel :: (x: int, y: int) {
	x0 := cast(float) x * DISPLAY_SCALE;
	y0 := cast(float) y * DISPLAY_SCALE;
	x1 := x0 + DISPLAY_SCALE;
	y1 := y0 + DISPLAY_SCALE;
	print("(%, %) (%, %)", x0, y0, x1, y1);
	Simp.immediate_quad(x0, y0, x1, y1, COLOR_ON);
}

clear_render_target :: () {
	C :: COLOR_OFF;
	Simp.clear_render_target(C.x, C.y, C.z, C.w);
}

// u16_to_bytes :: (val: u16) -> u8, u8 {
// 	return cast(u8)
// }
//
add_to_memory :: inline (val: $T, index: u16) {
	print("%", size_of(T));
	memcpy(memory.data + index, *val, size_of(T) / 8);
}

print_memory :: (data: [] u8) {
    // 1. Print the Column Header
    // We pad the start to match the 5-character wide address column
    print("       "); 
    for 0..15 {
        // formatInt(it, base=16) converts 10 -> "a"
        print("_% ", formatInt(it, base=16, capital_letters=true));
        if it < 15 print(" ");
    }
    print("\n");

    // 2. Iterate through memory
    for row: 0..(data.count/16)-1 {
        
        // Format the address label (e.g., "0x0_")
        // We use padding=5 to ensure "0x1_" and "0x100_" align
        addr_str := tprint("0x%_", formatInt(row, base=16, capital_letters=true));
        
        // Left pad the address string to 5 characters
        print("%  ", formatText("%", addr_str, padding=5));

        for col: 0..15 {
            byte_index := row * 16 + col;
            
            if byte_index < data.count {
                b := data[byte_index];
                // formatInt with minimum_digits=2 gives us the "02" effect
                print("% ", formatInt(b, base=16, minimum_digits=2, capital_letters=true));
            }
        }
        print("\n");
    }
}

push_to_stack :: (s: *Stack($T, $N), elt: T) {
	assert(s.ptr < s.data.count);
	if s.ptr < 0 then return;
	s.data[s.ptr] = elt;
	s.ptr += 1;
}

peek_stack :: (s: *Stack($T, $N)) {
	return s.data[s.ptr];
}

pop_from_stack :: (s: *Stack($T, $N)) -> T {
	res := s.data[s.ptr];
	s.ptr -= 1;
	return res;
}

FONT :: u8.[
	0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
	0x20, 0x60, 0x20, 0x20, 0x70, // 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
	0x90, 0x90, 0xF0, 0x10, 0x10, // 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
	0xF0, 0x10, 0x20, 0x40, 0x40, // 7
	0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, // A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
	0xF0, 0x80, 0x80, 0x80, 0xF0, // C
	0xE0, 0x90, 0x90, 0x90, 0xE0, // D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
	0xF0, 0x80, 0xF0, 0x80, 0x80  // F
];

TARGET_FPS :: 60;
TARGET_CYCLE_TIME :: #run to_apollo(1.0 / TARGET_FPS);
DISPLAY_SCALE :: 16;
WINW :: DISPLAY_SCALE * 64;
WINH :: DISPLAY_SCALE * 32;
COLOR_ON :: Vector4.{0.69, 0.55, 0.66, 1.0};
COLOR_OFF :: Vector4.{0.12, 0.12, 0.18, 1.0};

#import "Basic";
#import "Window_Creation";
Input :: #import "Input";
Simp :: #import "Simp";
Random :: #import "Random";
Math :: #import "Math";
Vector4 :: Math.Vector4;
