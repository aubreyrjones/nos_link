NOS LINK
========

This is a assembling linker, or linking assembler, for the 0x10c DCPU-16 v1.1.

It accepts Notch-style assembly code. You may specify as many assembly files as you wish, and they will be linked as assembled.

Prerequisites
-------------
You'll need ruby. I'm using 1.8; but, it should work with 1.9 as well.

You'll also need the 'trollop' rubygem. I use it for command-line arguments processing. This is the only ruby dependency.

Usage
-----

    nos_link -o output_binary assembly_module [space separated list of additional modules]

Try --help for more options.