PROGRAM_PATH :: "roms/8-scrolling.ch8";

// CHIP-8 emulator
main :: () {
	{
		using *context.print_style.default_format_int;
		base = 16;
		minimum_digits = 4;
		digits_per_comma = 4;
		comma_string = "_";
	}

	init_bit_array(*pixels, 64 * 32);
	// clear_all_bits(*pixels);
	init_bit_array(*key_states, 16);
	// clear_all_bits(*key_states);

	start_time := current_time_monotonic();
	quit := false;

	if !HEADLESS {
		the_window = create_window(window_name="Chip-8", width=WINW, height=WINH);
		Simp.set_render_target(the_window);
		Simp.set_shader_for_color();
		clear_render_target();
		Simp.swap_buffers(the_window);
	}

	chip8_initialize();

	last_cycle_time := current_time_monotonic();

	while !quit {
		if !HEADLESS {
			Input.update_window_events();
			//memset(*key_states, 0, size_of([16] u16));
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

			for Input.get_window_resizes() {
				Simp.update_window(it.window);

				redraw = true;
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
// 0x000-0x0FF - Call stack
// 0x100       - Stack pointer
// 0x101-0x1FF - Chip 8 interpreter (contains font set in emu)
// 0x050-0x0A0 - Used for the built in 4x5 pixel font set (0-F)
// 0x200-0xFFF - Program ROM and work RAM

memory: [4096] u8;
registers: [16] u8;
index_register: u16;
program_counter: u16;
pixels: Bit_Array; // 1 bit per pixel
stack_memory: [16] u16;
stack: [] u16 = ---;
// stack: Stack(u16, 16);

// Both timers count down at 60Hz
delay_timer: u8;
sound_timer: u8; // When this one reaches 0 it beeps

key_states: Bit_Array;

Stack :: struct($T: Type, $N: u64) {
	data: [N] T;
	ptr: u64; 
}

the_window: Window_Type;

INSTRUCTIONS :: enum u16 {
	SYSTEM             :: 0;
	JUMP               :: 0x1__000;
	CALL               :: 0x2__000;
	IF_NEQ             :: 0x3__000;
	IF_EQ              :: 0x4__000;
	IF_NEQ_REGISTER    :: 0x5__000;
	SET_REGISTER       :: 0x6__000;
	INCREMENT_REGISTER :: 0x7__000;
	REGISTER_MATH      :: 0x8__000; // register F = 1 on some occasions
	IF_EQ_REGISTER     :: 0x9__000;
	SET_INDEX_REGISTER :: 0xA__000;
	JUMP0              :: 0xB__000; // Jump to address + register 0 value
	RANDOM             :: 0xC__000;
	DRAW               :: 0xD__000; // register F = 1 on collision
	IF_KEY             :: 0xE__000;
	ASSIGN_SPECIAL     :: 0xF__000; // Assign special registers like timers, index etc
}

chip8_initialize :: () {
	stack.data = stack_memory.data;
	stack.count = 0;

	// Load font
	// memcpy(memory.data + 0x50, FONT.data, FONT.count);
	memcpy(*memory[0x50], PROGRAM.data, PROGRAM.count);
	program_counter = 0x200;

	// Load test program
	memcpy(*memory[0x200], PROGRAM.data, PROGRAM.count);
	// memcpy(memory.data + 0x200, PROGRAM.data, PROGRAM.count);
	print("-------------------------------------------------------------------\n");
	print("---------------------- CHIP-8 INITIALIZED -------------------------\n");
	print("-------------------------------------------------------------------\n");
	// print_memory((program_counter >> 4 - 1), (program_counter >> 4) + 1);
	print_memory(0x20, 0x27);
}

redraw := false;
last_op := 0;
// If returns false, the loop should stop
chip8_cycle :: (delta_time: float64, program_time: float64) -> bool {
	// --- Fetch
	if program_counter >= memory.count - 1 {
		log("Program counter exceeded memory space, exiting.");
		return false;
	}
	opcode : u16 = (cast(u16) memory[program_counter]) << 8 | memory[program_counter + 1];
	if last_op != opcode then print("0x%    %    ", program_counter, opcode);
	program_counter += 2;

	print_instruction :: (name: string, data: .. Any) #expand {
		if `last_op == `opcode then return;
		print("%", right_pad(name, 15));
		for data {
			print("% ", it);
		}
		print("\n");
	}

	// --- Decode
	// --- Execute opcode
	// https://johnearnest.github.io/Octo/docs/chip8ref.pdf
	if cast(INSTRUCTIONS) (opcode & 0xF000) == {
		case .SYSTEM;
			if opcode == {
				case 0x00e0; // clear
					print_instruction("CLEAR");
					clear_all_bits(*pixels);
				case 0x00ee; // RETURN
					location := pop(*stack);
					program_counter = location;
			}

		case .JUMP; 
			location := opcode & 0x0FFF;
			program_counter = location;
			print_instruction("JUMP", location);
		case .CALL; 
			location := opcode & 0x0FFF;
			stack.count += 1;
			stack[stack.count - 1] = program_counter;
			program_counter = location;
			print_instruction("CALL", location);
			// 		// Call subroutine at instruction_data
		case .IF_NEQ;
			reg_num := (opcode & 0x0F00) >> 8;
			value := (opcode & 0x00FF);
			if registers[reg_num] == cast(u8) value then program_counter += 2;
		case .IF_EQ; 
			reg_num := (opcode & 0x0F00) >> 8;
			value := (opcode & 0x00FF);
			if registers[reg_num] != cast(u8) value then program_counter += 2;
		case .IF_EQ_REGISTER; 
			reg_x_num := (opcode & 0x0F00) >> 8;
			reg_y_num := (opcode & 0x00F0) >> 4;
			if registers[reg_x_num] != registers[reg_y_num] then program_counter += 2;
		case .IF_NEQ_REGISTER; 
			reg_x_num := (opcode & 0x0F00) >> 8;
			reg_y_num := (opcode & 0x00F0) >> 4;
			if registers[reg_x_num] == registers[reg_y_num] then program_counter += 2;
		case .SET_INDEX_REGISTER;
			value := opcode & 0x0FFF;
			print_instruction("SET_INDEX_REG", value);
			index_register = value;
		case .SET_REGISTER; 
			reg_num := (opcode & 0x0F00) >> 8;
			value := cast(u8) (opcode & 0x00FF);
			print_instruction("SET_REGISTER", reg_num, value);
			registers[reg_num] = value;
		case .INCREMENT_REGISTER; 
			reg_num := (opcode & 0x0F00) >> 8;
			value := cast(u8) (opcode & 0x00FF);
			print_instruction("INC_REGISTER", reg_num, value);
			registers[reg_num] = registers[reg_num] + value;
		case .REGISTER_MATH;
			reg_x_num := (opcode & 0x0F00) >> 8;
			reg_y_num := (opcode & 0x00F0) >> 4;
			reg_x := *registers[reg_x_num];
			reg_y := registers[reg_y_num];
			reg_f := *registers[0xF];
			op := "";
			if opcode & 0x000F == {
				case 0;
					reg_x.* = reg_y;
					op = ":=";
				case 1;
					reg_x.* |= reg_y;
					op = "|=";
				case 2;
					reg_x.* &= reg_y;
					op = "&=";
				case 3;
					reg_x.* ^= reg_y;
					op = "^=";
				case 4;
					sum: u16 = reg_x.* + reg_y;
					reg_f.* = cast(u8) ifx sum > 0x00FF then 1 else 0;
					reg_x.* = cast(u8) (sum & 0x00FF);
					op = "+=";
				case 5;
					reg_f.* = cast(u8) ifx reg_x.* > reg_y then 1 else 0;
					reg_x.* -= reg_y;
					op = "-=";
				case 6;
					reg_f.* = cast(u8) reg_x.* & 0x01;
					reg_x.* >>= reg_y;
					op = ">>=";
				case 7;
					reg_f.* = cast(u8) ifx reg_y > reg_x.* then 1 else 0;
					reg_x.* = reg_y - reg_x.*;
					op = "=-";
				case 0xE;
					reg_f.* = cast(u8) reg_x.* & 0b10000000;
					reg_x.* <<= reg_y;
					op = "<<=";
			}
			print_instruction("REG_MATH", reg_x_num, op, reg_y_num, reg_y);
		case .JUMP0; 
			program_counter = registers[0] + (opcode & 0x0FFF);
			print_instruction("JUMP0", registers[0], opcode & 0x0FFF);
		case .RANDOM;
			reg_num := (opcode & 0x0F00) >> 8;
			value := (opcode & 0x00FF);
			res := xorshift() & value;
			registers[reg_num] = cast(u8) res;
			print_instruction("RAND", reg_num, value, res);
		case .DRAW; 
			redraw = true;
			sprite_x := registers[(opcode & 0x0F00) >> 8];
			sprite_y := registers[(opcode & 0x00F0) >> 4];
			n_bytes := opcode & 0x000F;
			print_instruction("DRAW", sprite_x, sprite_y, n_bytes, index_register);
			for i: 0..(n_bytes-1) {
				sprite := memory[index_register + i];
				y := (sprite_y + n_bytes - i) % 32;
				for j: 0..7 {
					x := (sprite_x + j) % 64;
					sprite_bit := ((sprite >> (7-j)) & 1) == 1;
					idx := (y * 64) + x;
					if pixels[idx] && (pixels[idx] != sprite_bit) then registers[0x0F] = 1;
					set_bit_to(*pixels, idx, pixels[idx] ^ sprite_bit);
				}
			}
		case .IF_KEY; 
			key_idx := registers[(opcode & 0x0F00) >> 8];
			if opcode & 0x00FF == {
				case 0x9E;
					if key_states[key_idx] then program_counter += 2;
				case 0xA1;
					if !key_states[key_idx] then program_counter += 2;
			}
		case .ASSIGN_SPECIAL;
			reg_num := (opcode & 0x0F00) >> 8;
			if opcode & 0x00FF == {
				case 0x0007;
					registers[reg_num] = delay_timer;
				case 0x000A;
					key_pressed := false;
					print("Waiting for key press...\n");
					while !key_pressed {
						for key_states {
							if !it continue;
							key_pressed = true;
							registers[reg_num] = cast(u8) it_index;
							break;
						}
					}
					print("Key pressed: %\n", registers[reg_num]);
				case 0x0015;
					delay_timer = registers[reg_num];
				case 0x0018;
					sound_timer = registers[reg_num];
				case 0x001E;
					index_register += registers[reg_num];
				case 0x0029;
					index_register = 0x50 + (5 * registers[reg_num]);
				case 0x0033;
					val := registers[reg_num];
					hundreds := val / 100;
					tens := val / 10 - hundreds * 10;
					ones := val - tens * 10 - hundreds * 100;
					memory[index_register] = hundreds;
					memory[index_register + 1] = tens;
					memory[index_register + 2] = ones;
				case 0x0055;
					memcpy(*memory + index_register, *registers, reg_num);
					// for i: 0..reg_num {
					// 	memory[index_register + i] = registers[i];
					// }
				case 0x0065;
					memcpy(*registers, *memory + index_register, reg_num);
			}
		case;
	}
	last_op = opcode;
	//print_registers();

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
	if redraw && !HEADLESS {
		clear_render_target();

		for pixels {
			if !it continue;
			x := it_index % 64;
			y := it_index / 64;
			draw_pixel(x, y);
		}

		Simp.swap_buffers(the_window);
		//print_pixels();
		redraw = false;
	}
	return true;
}

compile_seed :: #run cast(u32) to_microseconds(current_time_consensus()) & (cast(s64) Math.pow(2,4));
rng_state : u32 = 0;
xorshift :: inline () -> u8 {
	if rng_state == 0 {
		rng_state = cast(u32) (to_microseconds(current_time_consensus()) ^ compile_seed);
	}
	x := rng_state;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	rng_state = x;
	return cast(u8) (x & 0xFF);
}

draw_pixel :: inline (x: int, y: int) {
	x0 := cast(float) x * DISPLAY_SCALE;
	y0 := cast(float) y * DISPLAY_SCALE;
	x1 := x0 + DISPLAY_SCALE;
	y1 := y0 + DISPLAY_SCALE;
	// print("(%, %) (%, %)", x0, y0, x1, y1);
	Simp.immediate_quad(x0, y0, x1, y1, COLOR_ON);
}

clear_render_target :: inline () {
	using COLOR_OFF;
	Simp.clear_render_target(x, y, z, w);
}

print_memory :: (from := 0, to := 0xFF) {
	print("\nMEMORY      "); 
	for 0..15 {
		print("0%", FormatInt.{value=it, base=16});
		if it < 15 print(" ");
	}
	print("\n");

	for row: 0..(memory.count/16)-1 {
		if row < from || row > to then continue;

		addr_str := print("% (0x%)  ", FormatInt.{value=row, base=10, minimum_digits=3}, FormatInt.{value=row, base=16, minimum_digits=2});

		for col: 0..15 {
			byte_index := row * 16 + col;
			if byte_index < memory.count {

				b := memory[byte_index];
				str := FormatInt.{value=b, base=16, minimum_digits=2};
				if byte_index == program_counter then
				print("%%% ", "\e[1;31m", str, "\e[0m");
				else print("% ", str);

			}
		}
		print("\n");
	}
}

print_pixels :: () {
	// print("\n");
	// for pixels {
	// 	print(ifx it then "█" else "_");
	// 	if it_index % 64 == 0 then print("\n");
	// }
	// print("\n");
}

panic :: (err: string) {
	print("Panic: %s\n", err, to_standard_error = true);
	debug_break();
}

left_pad :: (str: string, size: int) -> string {
	builder: String_Builder;
	for str.count..size-1 {
		append(*builder, #char " ");
	}
	append(*builder, str);
	return builder_to_string(*builder,, temp);
}

right_pad :: (str: string, size: int) -> string {
	builder: String_Builder;
	append(*builder, str);
	for str.count..size-1 {
		append(*builder, #char " ");
	}
	return builder_to_string(*builder,, temp);
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

// 

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
DISPLAY_SCALE :: 8;
WINW :: DISPLAY_SCALE * 64;
WINH :: DISPLAY_SCALE * 32;
COLOR_ON :: Vector4.{0.69, 0.55, 0.66, 1.0};
COLOR_OFF :: Vector4.{0.12, 0.12, 0.18, 1.0};
TARGET_IS_LITTLE_ENDIAN :: true;
HEADLESS :: false;

PROGRAM :: #run -> string {
	file, ok := File.read_entire_file(PROGRAM_PATH);
	return file;
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
File :: #import "File";
#import "String";
#import "Bit_Array";
