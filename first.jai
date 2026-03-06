// CHIP-8 emulator
main :: () {
	start_time := current_time_monotonic();
	quit := false;

	the_window = create_window(window_name="Chip-8", width=WINW, height=WINH);
	Simp.set_render_target(the_window);
	Simp.set_shader_for_color();
	clear_render_target();
	Simp.swap_buffers(the_window);

	chip8_initialize();

	last_cycle_time := current_time_monotonic();

	while !quit {
		Input.update_window_events();
		memset(*key_states, 0, size_of([16] u16));
		for Input.events_this_frame {
			if it.type == .QUIT then quit = true;

			if it.type == {
				case .KEYBOARD;
					if it.key_pressed && table_contains(*KEYCODE_TO_CHIP8_KEY, cast(u16) it.key_code) {
						success, idx := table_find(*KEYCODE_TO_CHIP8_KEY, cast(u16) it.key_code);
						if success then key_states[idx] = true;
					}
			}
		}
		// print("%\n\n", key_states);

		now := current_time_monotonic();
		if now - last_cycle_time >= TARGET_CYCLE_TIME {
			quit = quit || !chip8_cycle(
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

key_states: [16] bool;

Stack :: struct($T: Type, $N: u64) {
	data: [N] T;
	ptr: u64; 
}

the_window: Window_Type;

chip8_initialize :: () {
	// Setup registers etc;
	
	// Load font
	memcpy(memory.data + 0x50, FONT.data, FONT.count);
	program_counter += 0x55;
}

// If returns false, the loop should stop
chip8_cycle :: (delta_time: float64, program_time: float64) -> bool {
	redraw := false;
	// print("% %\n", delta_time, program_time);
	// --- Fetch
	opcode_bytes: [] u8;
	opcode_bytes.data = memory.data + program_counter;
	opcode_bytes.count = 2;
	opcode = (cast(*u16) opcode_bytes.data).*;
	if TARGET_IS_LITTLE_ENDIAN then opcode = byte_swap(opcode);
	program_counter += 2;

	// --- Decode
	instruction_type : INSTRUCTION_TYPES = opcode_bytes[0] >> 4;
	instruction_data := opcode & 0x0FFF; 

	// --- Execute opcode
	// https://johnearnest.github.io/Octo/docs/chip8ref.pdf
	if instruction_type {
		case .SYSTEM;
			if opcode {
				case 0x00e0; // clear
				case 0x00ee; // exit subroutine
			}

		case .JUMP; 
			program_counter = instruction_data;
		case .CALL; 
			// Call subroutine at instruction_data
		case .IF_NEQ; 
		case .IF_EQ; 
		case .IF_EQ_REGISTER; 
		case .IF_NEQ_REGISTER; 
		case .ASSIGN; 
		case .ADD; 
		case .REGISTER_MATH; 
		case .JUMP0; 
		case .RANDOM; 
		case .SPRITE; 
		case .IF_KEY_PRESSED; 
		case .ASSIGN_SPECIAL; 
	}
	
	
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
	return true;
}

draw_pixel :: (x: int, y: int) {
	x0 := cast(float) x * DISPLAY_SCALE;
	y0 := cast(float) y * DISPLAY_SCALE;
	x1 := x0 + DISPLAY_SCALE;
	y1 := y0 + DISPLAY_SCALE;
	// print("(%, %) (%, %)", x0, y0, x1, y1);
	Simp.immediate_quad(x0, y0, x1, y1, COLOR_ON);
}

clear_render_target :: () {
	using COLOR_OFF;
	Simp.clear_render_target(x, y, z, w);
}

add_to_memory :: inline (val: $T, index: u16) {
	// print("%", size_of(T));
	val_copy := byte_swap(val);
	view: [] u8;
	view.data = cast(*u8) *val_copy;
	view.count = size_of(T);
	memcpy(memory.data + index, view.data, view.count);
}

print_memory :: (data: [] u8) {
    print("\n            "); 
    for 0..15 {
        print("0%", FormatInt.{value=it, base=16});
        if it < 15 print(" ");
    }
    print("\n\n");

    for row: 0..(data.count/16)-1 {
        
        addr_str := print("% (0x%)  ", FormatInt.{value=row, base=10, minimum_digits=3}, FormatInt.{value=row, base=16, minimum_digits=2});

        for col: 0..15 {
            byte_index := row * 16 + col;
            
            if byte_index < data.count {
                b := data[byte_index];
                print("% ", FormatInt.{value=b, base=16, minimum_digits=2});
            }
        }
        print("\n");
    }
}

peek :: (s: *Stack($T, $N)) -> T {
	return ifx s.ptr > 0 then s.data[s.ptr-1] else 0;
}

pop :: (s: *Stack($T, $N)) -> T {
	res := s.data[s.ptr];
	s.ptr -= 1;
	return res;
}

push :: (s: *Stack($T, $N), val: T) {
	if s.ptr == s.data.count - 1 {
		panic("Stack overflow");
		return;
	}
	s.data[s.ptr] = val;
	s.ptr += 1;
}

panic :: (err: string) {
	print("Panic: %s\n", err, to_standard_error = true);
	debug_break();
}

hex :: (n: $T) -> string {
	return tprint("%", FormatInt.{value=n, base=16});
}

bin :: (n: $T) -> string {
	return tprint("%", FormatInt.{value=n, base=2});
}

KEYCODE_TO_CHIP8_KEY :: #run -> Table(u16, u8) {
	t : Table(u16, u8);

	table_set(*t,64,0);      // A
	table_set(*t,90,1);      // Z
	table_set(*t,69,2);      // E
	table_set(*t,82,3);      // R

	table_set(*t, 81, 4);      // Q
	table_set(*t, 83, 5);      // S
	table_set(*t, 68, 6);      // D
	table_set(*t, 70, 7);      // F

	table_set(*t, 87, 8);      // W
	table_set(*t, 88, 9);      // X
	table_set(*t, 67, 10);     // C
	table_set(*t, 86, 11);     // V
	return t;
};

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
TARGET_IS_LITTLE_ENDIAN :: true;
INSTRUCTION_TYPES :: enum u8 {
	SYSTEM :: 0;
	JUMP :: 1;
	CALL :: 2;
	IF_NEQ :: 3;
	IF_EQ :: 4;
	IF_EQ_REGISTER :: 9;
	IF_NEQ_REGISTER :: 5;
	ASSIGN :: 6;
	ADD :: 7;
	REGISTER_MATH :: 8; // register F = 1 on some occasions
	JUMP0 :: 0xB; // Jump to address + register 0 value
	RANDOM :: 0xC;
	SPRITE :: 0xD; // register F = 1 on collision
	IF_KEY_PRESSED :: 0xE;
	ASSIGN_SPECIAL :: 0xF; // Assign special registers like timers, index etc
}

#import "Basic";
#import "Window_Creation";
Input :: #import "Input";
Simp :: #import "Simp";
Random :: #import "Random";
Math :: #import "Math";
Vector4 :: Math.Vector4;
#import "Bit_Operations";
#import "Hash_Table";
