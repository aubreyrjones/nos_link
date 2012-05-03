:global_hex
	.word 0x10
:string_ref
	.string "aaaaaaaaaaaaaaaaaaaaa"
:zero_str
	.asciz "bbbbbbbbbbbbbbbbbbbbbb"
:escaped_string
	.string "password is \"password\""
:mixed_string
	.word 0x23,"fnord",0x23
:global_dec
	.word 10
	.word 10
	.word 10
:negative
	.short -2331
	.word "mixed",0x00,"data",0x00
:comma_data
  .byte 0x10, 16, _end
:reference
	set a, [global_dec]
	set a, [global_dec+1]
	set a, [2+global_dec]

