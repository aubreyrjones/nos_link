

# stick consecutive name->number pairings into a hash
def declare(map, start, string)
  count = start
  string.split(" ").each do |token|
    map[token] = count
    count += 1
  end
end

def regex_keys(h)
  return /(#{h.keys.join(")|(")})/i
end

def parse_warning(filename, line_no, line_str, msg)
  puts "Parse Warning on line #{line_no} in #{filename}:"
  puts "\t#{msg}"
  puts "Line:\t#{line_str}"
end

class ParseError < Exception
  attr_accessor :msg
  def initialize(msg)
    @msg = msg
  end
end

class EvalError < Exception
  attr_accessor :msg
  def initialize(msg)
    @msg = msg
  end
end


class LinkError < Exception
  attr_accessor :msg
  def initialize(msg)
    @msg = msg
  end
end

INSTRUCTIONS = Hash.new
EXTENDED_INSTRUCTIONS = Hash.new
REGISTERS = Hash.new
VALUES = Hash.new

# Operational directives
DIRECTIVES = Hash.new
NULL_DIRS = Hash.new
DATA_DIRECTIVES = Hash.new
  
declare(INSTRUCTIONS, 1, "set add sub mul mli div dvi mod and bor xor shr asr shl sti ifb ifc ife ifn ifg ifa ifl ifu")
declare(INSTRUCTIONS, 0x1a, "adx sbx")
declare(EXTENDED_INSTRUCTIONS, 1, "jsr")
declare(EXTENDED_INSTRUCTIONS, 0x07, "hcf int iag ias")
declare(EXTENDED_INSTRUCTIONS, 0x10, "hwn hwq")
declare(REGISTERS, 0, "a b c x y z i j")
declare(VALUES, 0x18, "push peek pick sp pc ex")
declare(DATA_DIRECTIVES, 0x00, '.byte .short .word .uint16_t .string .asciz')
declare(DIRECTIVES, 0x00, ".private .hidden #{DATA_DIRECTIVES.keys.join(' ')} .data .text .func .endfunc")
declare(NULL_DIRS, 0x00, '.globl .global .extern .align .section .zero')

REV_REG = {}
REGISTERS.each_pair do |k, v|
  REV_REG[v] = k
end

REV_VALS = {}
VALUES.each_pair do |k, v|
  REV_VALS[v] = k
end

INDIRECT_REG_OFFSET = 0x08
INDIRECT_REG_NEXT_OFFSET = 0x10

INDIRECT_NEXT = 0x1e
LITERAL_NEXT = 0x1f
SHORT_LITERAL_OFFSET = 0x20

HEX_RE = /^(-)?0x([0-9a-f]+)$/i
DEC_RE = /^(-)?(\d+)$/

#definition of a legal label or source symbol
LABEL_RE = /[\._a-z]+[a-z0-9\._]+/i

LABEL_REF_TOK_RE = /^[\._a-z]+[a-z0-9\._]+$/i

#label definition token
LABEL_DEF = /^\s*(:#{LABEL_RE})|(#{LABEL_RE}:)\s*$/i

#instruction token
INSTR_RE = /^#{regex_keys(INSTRUCTIONS)}|#{regex_keys(EXTENDED_INSTRUCTIONS)}$/i

#Directive tokens
DIRECT_RE = /^#{regex_keys(DIRECTIVES)}$/i

NULL_DIR_RE = /^#{regex_keys(NULL_DIRS)}$/i

#register
REGISTER_RE = /^#{regex_keys(REGISTERS)}$/i

DATA_RE = /^#{regex_keys(DATA_DIRECTIVES)}$/i

class Param
  attr_reader :parse_tree, :mode_bits, :param_word

  def initialize(parse_tree, position)
    @position = position
    @parse_tree = parse_tree
  end
  
  def indirect?
    @parse_tree[:indirect]
  end
  
  def each_term(start_instr = nil)
    cur_expr = start_instr | @parse_tree
    while true
      if cur_expr[:term]
        yield term
      end
      if cur_expr[:rhs]
        cur_expr = cur_expr[:rhs]
      else
        break
      end
    end
  end
  
  def is?(term, type_sym)
    return term[:type] == type_sym
  end
  
  def has_type?(type_sym)
    each_term do |term|
      if is?(term, type_sym)
        return true
      end
    end
    
    false
  end
 
  # Get a reconstructed textual representation of this parameter,
  # without indirection brackets.
  def expr_to_s
    buf = ''
    each_term do |term|
      if term[:operator]
        buf << term[:operator]
      end
      buf << term[:token]
    end
    buf
  end

  # Get a reconstructed textual rep of this parameter.
  def to_s
    template = indirect? ? "[%s]" : "%s"
    return template % expr_to_s
  end

  # Does this parameter demand an additional word in the instruction?
  # Right now, short form is unsupported.
  def needs_word?
    if has_type? :reference
      return true
    end
    
    if has_type? :literal
      return true
    end
    
    #otherwise it is only a register or raw special value
    return false
  end
  
  def rec_eval(scope, term, state)
    if is?(term, :register) || is?(term, :special)
      unless state[:register].nil? && state[:special].nil?
        raise EvalError.new("Only one register or special value may be referenced per expression.")
      end
      
      unless state[:accum].nil? || !term[:rhs].nil?
        raise EvalError.new("Registers and special values may only appear as left- or right-most term of an expression.")
      end
      
      if is?(term, :register)
        state[:register] = REGISTERS[term[:token]]
        state[:reg_tok] = term[:token]
      else
        state[:special] = VALUES[term[:token]]
        state[:special_tok] = term[:token]
      end
    elsif is?(term, :literal) || is?(term, :reference)
      state[:accum] = 0 if state[:accum].nil?
      loc_value = 0
      
      if is?(term, literal)
        loc_value = term[:value]
      else
        loc_value = scope.ref(term[:token]).def_instr.address
      end
        
      if term[:operator] && term[:operator] == '-'
        state[:accum] -= loc_value
      else
        state[:accum] += loc_value
      end
    end

    if term[:rhs]
      rec_eval(scope, term[:rhs], state)
    end

    return state
  end

  def evaluate(scope)
    state = {}
    rec_eval(scope, @parse_tree, state)
    
    if state[:register]
      if state[:accum]
        raise EvalError.new("There is no 'register+next' direct adressing mode.") unless indirect?
        state[:mode] = state[:register] + INDIRECT_REG_NEXT_OFFSET
        state[:offset] = state[:accum]
      elsif indirect?
        state[:mode] = state[:register] + INDIRECT_REG_OFFSET
      else
        state[:mode] = state[:register]
      end
    elsif state[:special]
      evaluate_special_state(state)
    elsif state[:accum]
      state[:mode] = indirect? ? INDIRECT_NEXT : LITERAL_NEXT
      state[:offset] = state[:accum]
    end
    
    @mode_bits = state[:mode]
    @param_word = state[:offset]
    
    state
  end
  
  def evaluate_special_state(state)
    case state[:special_tok]
    when 'pop'
    when 'push'
      raise EvalError.new("pop and push cannot be indirect.") if indirect?
      raise EvalError.new("pop and push do not accept offsets.") if state[:accum]
      if (state[:special_tok] == 'pop' && @position != 1) || (state[:special_tok] == 'push' && @position != 0)
        raise EvalError.new("pop or push used in wrong position.")
      end
      state[:mode] = VALUES('push')
    when 'sp'
      if state[:accum] && indirect?
        state[:mode] = VALUES('pick')
        state[:offset] = state[:accum]
      elsif indirect?
        state[:mode] = VALUES('peek')
      else
        state[:mode] = VALUES('sp')
      end
    when 'pc'
      raise EvalError.new("Only direct addressing with no offset is supported for pc.") if (indirect? || state[:accum])
      state[:mode] = VALUES('pc')
    when 'ex'
      raise EvalError.new("Only direct addressing with no offset is supported for ex.") if (indirect? || state[:accum])
      state[:mode] = VALUES('ex')
    end
  end
end

class NullInstruction
  attr_reader :address, :abs_line
  attr_accessor :a, :b, :source, :scope, :defined_symbols
  
  def initialize(defined_symbols)
    @abs_line = {:original_line => ';nil instruction', :directive => '.nil_instr'}
    @defined_symbols = defined_symbols
    @source = '[none]'
  end

  # Fix this instruction to a particular address in the program.
  def fix(address)
    @address = address
  end

  def realize
    
  end

  # Get the size, in words, of the instruction.
  def size
    0
  end

  # Get the binary words for this instruction.
  def words
    []
  end
  
  def to_s
    labels = @defined_symbols.map{|label| ":#{label.name}"}.join("\n")
    labels << "\n" unless labels.empty?
    addr_line = @address ? "\t; [0x#{address.to_s(16)}]" : ''
    return "#{labels}\t; null_instruction #{@a.to_s}#{@b ? ',' : ''} #{@b.to_s}#{addr_line}"
  end
  
end

class Instruction
  attr_reader :address, :abs_line
  attr_accessor :source, :scope, :defined_symbols, :params
  
  def initialize(source_file, global_scope, labels, parsed_line)
    @abs_line = parsed_line
    @source = source_file
    @scope = global_scope
    @defined_symbols = labels
    @params = []
    parsed_line[:params].each_with_index do |p, i|
      @params << Param.new(p, i)
    end
    @module = AsmSymbol::make_module_name(source_file)    
  end
  
  def line
    return @abs_line[:original_line]
  end

  # Fix this instruction to a particular address in the program.
  def fix(address)
    @address = address
  end

  # Evaluate the parameters with the given scope.
  def realize(scope)
    @params.each do |p|
      p.evaluate(scope)
    end
  end
  
   # Get the size, in words, of the instruction.
  def size
    puts "this should be subclassed."
  end

  # Get the binary words for this instruction.
  def words
    puts "this should be subclassed"
  end

  # Reconstruct a string rep of this instruction.
  def to_s
    labels = @defined_symbols.map{|label| ":#{label.name}"}.join("\n")
    labels << "\n" unless labels.empty?
    addr_line = @address ? "\t; [0x#{address.to_s(16)}]" : ''
    return "#{labels}\t#{@opcode_token} #{@a.to_s}#{@b ? ',' : ''} #{@b.to_s}#{addr_line}"
  end
end

class Op < Instruction
  def initialize(source_file, global_scope, labels, parsed_line)
    super(source_file, global_scope, labels, parsed_line)
    @instr_token = @abs_line[:instr]
    @op = INSTRUCTIONS[@instr_token]

    if @op.nil?
      @op = EXTENDED_INSTRUCTIONS[@opcode_token]
      if @op.nil?
        puts "Unknown instruction: #{@opcode_token}"
        exit 1
      end
      @extended = true
    end
  end
  
  # Get the size, in words, of the instruction.
  def size
    1 + params_size
  end
 
 # Get how many words of parameters are needed
  def params_size
    accum = 0
    @params.each do |p|
      accum += 1 if p.needs_word?
    end
    accum
  end

  # Get the binary words for this instruction.
  def words
    [opcode].concat(@params.map{|p| p.param_word})
  end

  # Get the opcode for this instruction.
  def opcode
    if @extended
      return 0x00 | (@op << 5) | (@params[0].mode_bits << 10)
    else
      return @op | (@params[1].mode_bits << 10) | (@params[0].mode_bits << 5)
    end
  end
 
    # Reconstruct a string rep of this instruction.
  def to_s
    labels = @defined_symbols.map{|label| ":#{label.name}"}.join("\n")
    labels << "\n" unless labels.empty?
    addr_line = @address ? "\t; [0x#{address.to_s(16)}]" : ''
    return "#{labels}\t#{@opcode_token} #{@a.to_s}#{@b ? ',' : ''} #{@b.to_s}#{addr_line}"
  end

end

# Inline data definition
class InlineData
  attr_reader :words
  attr_reader :address, :symbol_reference
  attr_accessor :source, :scope, :defined_symbols, :abs_line

  def initialize(source_file, global_scope, labels, abstract_line = nil)
    @abs_line = abstract_line
    @scope = global_scope
    @source = source_file
    @defined_symbols = labels
    @module = AsmSymbol::make_module_name(source_file)

    @words = []

    if abstract_line
      parse_data
    end
  end

  def line
    @abs_line[:line_number]
  end
  
  def parse_data
    if @abs_line[:directive] =~ /(string)|(asciz)/i
      str = @abs_line[:directive_rem].strip[1..-2]
      str.each_byte do |byte|
        @words << byte #this is okay, just the values
      end
      
    # @words.map!{|w| w | 0xff00}
      
      if @abs_line[:directive] =~ /asciz/
        @words << 0x0
      end
      return
    end
      
    if @abs_line[:directive]=~ /(byte)|(word)|(uint16_t)|(short)/i
      literals = @abs_line[:directive_rem].gsub(/\s+/, '').split(",")
      literals.each do |lit|
        if lit.nil?
          puts "BAD"
        end
        
        neg = 1
        if lit.start_with?('-')
          neg = -1
        end
        
        if lit =~ HEX_RE
          @words << $1.to_i(16) * neg
        elsif lit =~ DEC_RE   
          @words << $1.to_i(10)
        elsif lit =~ LABEL_RE
          @words << lit
        end
      end
    end
  end

  # Fix this instruction to a particular address in the program.
  def fix(address)
    @address = address
  end

  # Build the binary representation of the entire instruction,
  # including any additional words.
  def realize
    @words.map! do |word|
      if word.is_a? AsmSymbol
        if word.def_instr.address.nil?
          raise LinkError.new("Cannot find address of #{word.name}")
        end
        word.def_instr.address
      else
        word
      end
    end
  end

  def size
    return @words.size
  end

  def words_to_s_map
    @words.map do |word|
      if word.is_a? String
        "\t.word #{word}"
      elsif word.is_a? AsmSymbol
        "\t.word #{word.name}"
      elsif word.is_a? Numeric
        "\t.word 0x#{word.to_s(16)}"
      end
    end
  end

  def to_s
    labels = @defined_symbols.map{|label| ":#{label.name}"}.join("\n")
    labels << "\n" unless labels.empty?
    addr_line = @address ? "\t; [0x#{address.to_s(16)}]" : ''
    words = words_to_s_map
    if words.size > 0
      words[0] << addr_line
    end
    return "#{labels}#{words.join("\n")}"
  end
end


LINKAGE_VISIBILITY = [:global, :local, :hidden]
#A symbol. It might or might not be defined.
#By default, all symbols have a global visibility
#
#Private symbols are mangled before insertion into
#the program assembly. Not before.
#
#
class AsmSymbol
  attr_reader :orig_name, :def_instr, :linkage_vis, :first_file
  
  def initialize(first_file, orig_name, parent_symbol = nil)
    @orig_name = orig_name
    @first_file = first_file
    @parent = parent_symbol
    @linkage_vis = parent_symbol.nil? ? :global : :local
    @dependent_locals = []
    @referenced = false
  end
  
  def referenced
    @referenced = true
  end
  
  def referenced?
    @referenced
  end

  # Set the instruction or data word that defines this symbol.
  def define(instruction)
    @def_instr = instruction
  end

  # Set the visibility to hidden/private
  def make_hidden
    @linkage_vis = :hidden
  end

  # Is this a local symbol?
  def local?
    return @linkage_vis == :local
  end

  # Attach a local symbol to this global scope.
  def attach_local(local_sym)
    @dependent_locals << local_sym
  end

  # Get all dependent local symbols.
  def dependent_locals
    @dependent_locals
  end
  
  # Get the mangled name of this symbol.
  def name
    case @linkage_vis
    when :global
      return @orig_name
    when :local
      return AsmSymbol::make_local_name(@parent, @orig_name)
    when :hidden
      #the first file will always be the correct file for private symbols.
      return AsmSymbol::make_private_name(@first_file, @orig_name)
    else 
      puts "Unsupported linkage visibility of #{@linkage_vis}"
      exit 1
    end
  end

  # Mangle a local name.
  def self.make_local_name(parent_symbol, label)
    return "#{parent_symbol.name}$$#{label}"
  end

  # Mangle a private name.
  def self.make_private_name(filename, name)
      return "#{make_module_name(filename)}$$#{name}"
  end

  # Generate a module name from a filename.
  def self.make_module_name(filename)
    filename.gsub(/^\.+/, '').gsub('/', '_')
  end
end

class NosFunction
  attr_accessor :name, :mod, :symbol, :first_instr, :last_instr
  
  def initialize(name)
    @name = name
  end
end

class AsmModule
  attr_reader :name, :filename, :parse_tree, :instructions, :symbols, :functions
  
  def initialize(filename, parse_tree, instructions, symbols, functions)
    @name = AsmSymbol::make_module_name(filename)
    @filename = filename
    @parse_tree = parse_tree
    @instructions = instructions
    @symbols = symbols
    @functions = functions
  end
end