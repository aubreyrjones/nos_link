require File.expand_path(File.dirname(__FILE__) + '/resolve.rb')


def link_error_stop(e, filename, abs_line)
  puts "FATAL LINK ERROR"
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
  def initialize(symbols, modules)
    @symbols = symbols
    @modules = modules
    
    define_special_labels()
  end
  
  def define_special_labels
    @end_symbol = AsmSymbol.new("[none]", '_end', nil)
    @end_symbol.define(NullInstruction.new)
    @symbols[@end_symbol.name] = @end_symbol
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
      @iter = InstrIter.new(@modules)
    end
    return @iter
  end
  
  class InstrIter
    def initialize(mods)
      @mods = mods
    end
    
    def size
      accum = 0
      @mods.each do |mod|
        accum += mod.instructions.size
      end
    end
    
    def each
      @mods.each do |mod|
        mod.instructions.each do |instr|
          yield instr
        end
      end
    end
  end

  # Resolve all instruction parameters.
  # At this stage, the program is done in an abstract sense.
  # All that's left is turning the abstract instructions into binary.
  def assemble
    instructions.each do |instr|
      begin
        next unless instr.class == Instruction
        resolve_param(instr, instr.a)
        resolve_param(instr, instr.b)
      rescue LinkError => e
        link_error_stop(e, instr.source, instr.abs_line)
      end
    end
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
    @end_symbol.def_instr.fix(assembled_address)
  end

  # Have each instruction generate its binary code.
  def realize
    instructions.each do |instr|
      begin
        instr.realize
      rescue LinkError => e
        link_error_stop(e, instr.source, instr.abs_line)
      end
    end
  end

  # Write the binary into the given stream.
  def binary(output)
    if instructions.size == 0
      puts "No instruction stream. Cannot create binary."
      error 1
    end

    instructions.each do |instr|
      instr_bytes = instr.words
      encstr = 'n' * instr_bytes.size
      output << instr_bytes.pack(encstr)
    end
  end

  # Print a side-by-side assembly/binary listing.
  def print_hex_and_instr
    instructions.each do |instr|
      instr_bytes = instr.words
      fstr = "%x " * instr_bytes.size
      puts "#{instr.to_s} \t ;#{fstr % instr_bytes}"
    end
  end

  # Resolve an instruction's parameter.
  def resolve_param(instr, param)
    if param.nil? || param.reference_token.nil?
      return
    end

    ref_sym = resolve(@symbols, instr.source, param.reference_token, instr.scope)
    if ref_sym.nil?
      raise LinkError.new("Unfulfilled link error. Trying to find: #{param.reference_token}")
    end

    param.resolve(ref_sym)
  end
end
