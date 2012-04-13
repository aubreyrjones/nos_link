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
    @binary = ''
  end

  def fix
    assembled_address = 0
    @instructions.each do |instr|
      instr.fix(assembled_address)
      assembled_address += instr.size
    end
  end

  def assemble
    @binary = ''
    @instructions.each do |instr|
      resolve_param(instr, instr.a)
      resolve_param(instr, instr.b)
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
  end
end
