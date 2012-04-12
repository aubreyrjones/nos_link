:simple_test
	set pc, .local_test
:.local_test
	set pc, simple_test
  .hidden pre_private_test
:pre_private_test
  set pc, pre_private_test
:post_private_test
  set pc, post_private_test
:.local_test
  set pc, post_private_test
  .hidden post_private_test
:inline_test set pc, simple_test
