	.func func_def_a
:func_def_a
	set pc, func_def_b
	.endfunc

	.func func_def_b
:func_def_b
	set pc, func_def_a
	.endfunc

	.func func_def_c
:func_def_c
	set pc, func_def_a
	.endfunc
