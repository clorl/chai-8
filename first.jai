// CHIP-8 emulator
main :: () {
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

pixels: [64 * 32] u8;

// Both timers count down at 60Hz
delay_timer: u8;
sound_timer: u8; // When this one reaches 0 it beeps

key_states: [16] u8;

Stack :: struct($T: Type, $N: s64) {
	data: [N] T;
	ptr: s64; 
}

chip8_initialize :: () {
	// Setup registers etc;
}

chip8_cycle :: () {
	// Fetch opcode
	// Decode opcode
	// Execute opcode
	// Update timers
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

#import "Basic";
