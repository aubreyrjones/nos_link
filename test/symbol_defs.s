:global_test
	set pc, .local_testA
:.local_testA
	set pc, global_test
  .hidden pre_private_test
:pre_private_test
  set pc, pre_private_test
:post_private_test
  set pc, post_private_test
:.local_testB
  set pc, post_private_test
  .hidden post_private_test
:inline_test set pc, global_test


