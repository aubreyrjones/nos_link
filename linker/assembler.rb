require File.expand_path(File.dirname(__FILE__) + '/resolve.rb')

#
#
# Responsible for resolving references while
# also building the binary. Woo!
#
class Assemblinker
  def initialize(symbols, instructions)
    @symbols = symbols
    @instructions = instructions
  end

  def fix
    assembled_address = 0
    @instructions.each do |instr|
      instr.fix(assembled_address)
      assembled_address += instr.size
    end
  end

  def assemble
    @instructions.each do |instr|
      resolve_param(instr, instr.a)
      resolve_param(instr, instr.b)
    end
  end

  def realize
    @instructions.each do |instr|
      instr.realize
    end
  end

  def binary(output)
    if @instructions.size == 0
      puts "No instruction stream. Cannot create binary."
      error 1
    end

    @instructions.each do |instr|
      instr_bytes = instr.bytes
      encstr = 'v' * instr_bytes.size
      output << instr_bytes.pack(encstr)
    end
  end

  def print_hex_and_instr
    @instructions.each do |instr|
      instr_bytes = instr.bytes
      fstr = "%x " * instr_bytes.size
      puts "#{instr.to_s} \t #{fstr % instr_bytes}"
    end
  end

  def resolve_param(instr, param)
    if param.nil? || param.reference_token.nil?
      return
    end

    ref_sym = resolve(@symbols, instr.source, param.reference_token, instr.scope)
    if ref_sym.nil?
      puts "Unfulfilled link error. Trying to find: #{param.reference_token}"
      exit 1
    end

    param.resolve(ref_sym.def_instr.address)
  end
end
