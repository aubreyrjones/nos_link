	.asciz "Strings are an easy way to get words."
:neg_ref_label
	set a, [-0x2+neg_ref_label]
	set b, [neg_ref_label - 4]
	set c, [neg_ref_label-0x3]