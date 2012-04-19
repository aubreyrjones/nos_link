NOS LINK
========

This is a assembling linker, or linking assembler, for the 0x10c DCPU-16 v1.1.

It accepts Notch-style assembly code. You may specify as many assembly files as you wish, and they will be linked as assembled.


Prerequisites
-------------
You'll need Ruby 1.9+. Or jRuby 1.6+. They should operate identically, but the startup time on jRuby is three times longer. [Ruby 1.8 used to be supported, but there are several significant improvements in 1.9.]

If you're running apt-based linux, here is the basic recipe to get up to speed. This may not be the ideal way to install this stuff, but it's the easiest. rpm- or source-based distros will use basically the same approach.

    > sudo apt-get install ruby1.9

On windows, I'm not entirely sure what to do. But, you need to install ruby from http://www.ruby-lang.org.

On osx... you have ruby 1.8 as the default. I'm not sure what you need to do. Soon, nos will be available as an entire development environment and will ship with jRuby.

Usage
-----

    nos_link assembly_module [space separated list of additional modules]

The default output file is 'out.dcpu16' in the current directory. If you want something else, the '-o' command line switch will allow you to specify any name you like.

Try --help for more information and options.


Assembler Syntax and Directives
------------------------------

nos_link accepts Notch-style label names, or traditional label names. These differ only in the location of the colon.

Labels may be any collection of letters, numbers, periods, and underscores. They must not start with a digit.

Labels named identically to register names (a, x, i, j...) or operand value names (push, pop, pc, sp...) will be masked by the register they shadow. This means that if you have a label defined with ':a', it cannot be referenced by any instruction parameter--the expression will be interpreted as the 'a' register instead.

Any label starting with a '.' will be treated as local. They are bound to the most immediately preceeding global label. Local labels may only be referenced by instructions in the same global label scope.

```dasm16
:expon
  set a, 0x42
  set b, 0x42
:.local_label
  mul a, b
  set pc, .local_label
```

Instruction  Parameters
-----------------------

Instruction parameters have their own little syntax. The basic syntax is something like

    offset + label + register 

If it's an indirect reference, it will look like

    [offset + label + register]

Any of offset, label, or register may be absent. And may be in any order. The offset may be negative.

    
Currently the only actively supported assembler directive is '.hidden' (which may also be spelled '.private'). The .hidden directive indicates to the linker that the given label is not available for reference from the rest of the program. Additionally, it indicates that the .hidden symbol should be preferred to global symbols of the same name for references from within the same assembly module.

The syntax is:


    .hidden symbol_name


Example: 

```dasm16
.hidden expon
:expon
  set a, 0x42
  set b, 0x42
:.local_label
  mul a, b
  set pc, .local_label
```

Data can be inlined into assembly modules either as individual words, or as text strings.

Example:

```dasm16
:single_word_example
  .word 0x10 ; encode the literal value 16
  .uint16_t 0x10 ; .uint16_t is an alias for .word
:string_example
  .string "This is a string."
:zero_terminated_string
  .asciz "This is a zero-terminated string."
```

(There is currently no support for the comma-separated numeric literals style.)
