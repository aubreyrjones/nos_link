require_relative 'resolve.rb'

def link_error_stop(e, filename, abs_line)
  puts "FATAL LINK ERROR"
  puts "Error: #{e.msg}"
  puts "in file #{filename} on line #{abs_line[:line_number] + 1}"
  puts "Errant Line: #{abs_line[:original_line]}"
  puts e.backtrace if $config[:hacking]
  exit 1 unless $DONT_STOP_ON_ERROR
end

def eval_error_stop(e, filename, abs_line)
  puts "FATAL EVAL ERROR"
  puts "Error: #{e.msg}"
  puts "in file #{filename} on line #{abs_line[:line_number] + 1}"
  puts "Errant Line: #{abs_line[:original_line]}"
  puts e.backtrace if $config[:hacking]
  exit 1 unless $DONT_STOP_ON_ERROR
end

#
#
# Responsible for resolving references while
# also building the binary. Woo!
#
class Assemblinker
  attr_reader :symbols, :modules

  def initialize(symbols, modules)
    @symbols = symbols
    @modules = modules
    @leading_instructions = []
    @trailing_instructions = []
    
    define_special_labels()
  end
  
  def define_special_labels
    @end_symbol = AsmSymbol.new("[none]", '_end', nil)
    @end_symbol.define(NullInstruction.new([@end_symbol]))
    @symbols[@end_symbol.name] = @end_symbol
    @trailing_instructions << @end_symbol.def_instr
  end
  
  def instr_list
    list = []
    instructions.each do |instr|
      list << instr
    end
    list
  end
  
  def instructions
    if @iter.nil?
      @iter = InstrIter.new(@modules, @leading_instructions, @trailing_instructions)
    end
    return @iter
  end
  
  class InstrIter
    def initialize(mods, leading, trailing)
      @leading = leading
      @mods = mods
      @trailing = trailing
    end
    
    def size
      accum = 0
      @mods.each do |mod|
        accum += mod.instructions.size
      end
    end
    
    def each      
      @leading.each do |instr|
          yield instr
      end
      
      @mods.each do |mod|
        mod.instructions.each do |instr|
          yield instr
        end
      end
      
      @trailing.each do |instr|
          yield instr
      end
    end
  end

  def assemble
  end
  
  # Get a list of all unreferenced symbols in the program.
  def get_unref_symbols
    unref = []
    @modules.each do |mod|
      mod.symbols.values.each do |s|
        unless s.referenced?
          unref << s.name
        end
      end
    end
    unref
  end

  # Fix all instructions into their address space.
  def fix
    assembled_address = $config[:base_address]
    instructions.each do |instr|
      instr.fix(assembled_address)
      assembled_address += instr.size
    end
  end

  # Have each instruction generate its binary code.
  def realize
    refscope = ReferenceScope.new
    refscope.symbol_table = @symbols
    instructions.each do |instr|
      begin
        refscope.filename = instr.source
        refscope.parent = instr.scope
        instr.realize(refscope)
      rescue LinkError => e
        link_error_stop(e, instr.source, instr.abs_line)
      rescue EvalError => e
        eval_error_stop(e, instr.source, instr.abs_line)
      rescue Exception => e
        puts e.backtrace
        link_error_stop(LinkError.new(e.message), instr.source, instr.abs_line)
      end
    end
  end

  def pack_string(words)
    str = ''
    words.each do |word|
      if word < 0 
        if word < $MIN_SHORT
          raise EvalError.new("Negative word value #{word} is less than #{$MIN_SHORT}.") 
        end
        str << SHORT_PACK_SYMBOL
      else
        if word > $MAX_WORD
          raise EvalError.new("Word value #{word} is greater than #{$MAX_SHORT}")
        end
        str << WORD_PACK_SYMBOL
      end
    end
    str
  end
  
  # Write the binary into the given stream.
  def binary(output)
    if instructions.size == 0
      puts "No instruction stream. Cannot create binary."
      exit 1
    end

    instructions.each do |instr|
      instr_bytes = instr.words
      encstr = pack_string(instr_bytes)
      output << instr_bytes.pack(encstr)
    end
  end

  def split_up_instruction(instr_word)
    "(%x|%x|%x) %x " % [(instr_word & 0xfc00) >> 10, (instr_word & 0x03e0) >> 5, (instr_word & 0x001f), instr_word]
  end

  # Print a side-by-side assembly/binary listing.
  def print_hex_and_instr
    instructions.each do |instr|
      binstr = nil
      instr_bytes = instr.words
      if instr.words && instr.words.size > 0
        encstr = pack_string(instr_bytes)
        binary = instr_bytes.pack(encstr)
        unpacked = binary.unpack(WORD_PACK_SYMBOL * instr_bytes.size)
        unless instr.is_a?(Op)
          fstr = "%x " * unpacked.size
          binstr = fstr % unpacked
        else
          binstr = split_up_instruction(unpacked.shift)
          fstr = "%x " * unpacked.size
          binstr << fstr % unpacked
        end
      end
      
      puts "#{instr.to_s_eval} \t ; #{binstr}"
    end
  end
  
  # Print a side-by-side assembly/binary listing.
  def print_instr_debug
    instructions.each do |instr|
      instr_bytes = instr.words
      fstr = "%x " * instr_bytes.size
      puts "#{instr.to_s_eval} \t ;#{fstr % instr_bytes}"
    end
  end
end
