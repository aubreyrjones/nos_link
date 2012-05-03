NOS LINK
========

This is an assembling linker, or linking assembler, for the 0x10c DCPU-16 v1.7.

It accepts Notch-style assembly code. You may specify as many assembly files as you wish, and they will be linked and assembled into a single binary.

References and symbols are tracked. As the core stabilizes, this will allow for several powerful optimizations and features.


Prerequisites
-------------
You'll need Ruby 1.9+. Or jRuby 1.6+ in 1.9 mode. They should operate identically, but the startup time on jRuby is much longer than the time it takes to actually link and assemble a program.

If you're running apt-based linux, here is the basic recipe to get up to speed. This may not be the ideal way to install this stuff, but it's the easiest. rpm- or source-based distros will use basically the same approach.

    > sudo apt-get install ruby1.9 rubygems1.9
    > sudo gem install treetop

On windows, I'm not entirely sure what to do. But, you need to install ruby from http://www.ruby-lang.org. And you need to install http://rubygems.org.

If you're a ruby or nos hacker, or on OSX, I strongly suggest you install and use RVM. On OSX, this may be required to get a good ruby
1.9 implementation. http://rvm.io


Usage
-----

```
nos_link assembly_module [space separated list of additional modules]
```

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

    (offset arithmetic) + label + register 

If it's an indirect reference, it will look like

    [(offset arithmetic) + label + register]

Any of offset, label, or register may be absent. And may be in any order. The offset may be negative, and subtraction is supported. Evaluated negative offsets will be encoded in 2's complement form, which, when added to the register will result in subtraction. 

Data can be inlined into assembly modules either as individual words, or as text strings, or as a mix of both. There is currently no support for escaping quotation marks inside strings.

Data may be started with a wide array of pseudo-ops, all roughly exactly the same thing--except for one. There is only one real datatype, the word. Encoding is determined only by whether or not the final evaluated value of an offset is positive or negative.

The one exception is ".asciz". This directive accepts the standard data arguments, but then appends a null word (with the value 0) to the end of the explicitly encoded data.

Example:

```dasm16
:single_word_example
  .word 0x10 ; encode the literal value 16
  .uint16_t 0x10 ; .uint16_t is an alias for .word
  .short -123 ; you can encode a negative value
  .word 34+12-2 ; addition and subtraction are supported
  .word reference + 4 ; here's arithmetic with references! woo!
:string_example
  .string "This is a string."
  .string "This is",0xff12,"mixed",-23,"data"
  .short "it really doesn't matter the directive"
:zero_terminated_string
  .asciz "This is a zero-terminated string."
  .asciz "this",0x23,"mixed data gets zero terminated"
:address_of_string
  .word string_example
```

    
Currently the only actively supported assembler directive is '.hidden' (which may also be spelled '.private'). The .hidden directive indicates to the linker that the given label is not available for reference from the rest of the program. Additionally, it indicates that the .hidden symbol should be preferred to global symbols of the same name for references from within the same assembly module.

The syntax is:

```
.hidden symbol_name
```
