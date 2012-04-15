:global_hex
	.word 0x10
:string_ref
	.string "aaaaaaaaaaaaaaaaaaaaa"
:zero_str
	.asciz "bbbbbbbbbbbbbbbbbbbbbb"
:global_dec
	.word 10
	.word 10
	.word 10
:reference
	set a, [global_dec]
	set a, [1+global_dec]
	set a, [2+global_dec]

