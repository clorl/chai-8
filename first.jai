#!/usr/bin/env jai
build :: () {
    set_build_options_dc(.{do_output=false});

	w := compiler_create_workspace();
	if !w {
		print("Workspace creation failed.\n");
		return;
	}

	opt := get_build_options(w);
	opt.output_executable_name = "program";
	opt.shorten_filenames_in_error_messages = true;
	set_optimization(*opt, .VERY_DEBUG);
	set_build_options(opt, w);
	add_build_file("main.jai", w);
}

#run build();
#import "Compiler";
#import "Basic";
