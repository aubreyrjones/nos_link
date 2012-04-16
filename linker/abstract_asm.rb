

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


INSTRUCTIONS = Hash.new
EXTENDED_INSTRUCTIONS = Hash.new
REGISTERS = Hash.new
VALUES = Hash.new

# Operational directives
DIRECTIVES = Hash.new
NULL_DIRS = Hash.new
  
declare(INSTRUCTIONS, 1, "set add sub mul div mod shl shr and bor xor ife ifn ifg ifb")
declare(EXTENDED_INSTRUCTIONS, 1, "jsr")
declare(REGISTERS, 0, "a b c x y z i j h")
declare(VALUES, 0x18, "pop peek push sp pc o")
declare(DIRECTIVES, 0x00, '.private .hidden .word .uint16_t .string .asciz .data .text .func .endfunc')
declare(NULL_DIRS, 0x00, '.globl .global .extern .align')

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

HEX_RE = /^0x([0-9a-f]+)$/i
DEC_RE = /^(\d+)$/

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



class Param
  attr_accessor :offset, :reference_token, :reference_symbol, :register, :indirect, :embed_r

  def initialize(parse_table)
    @offset = parse_table[:offset]
    @reference_token = parse_table[:reference]
    @register = parse_table[:register]
    @indirect = parse_table[:indirect]
    @value = parse_table[:value]
    @embed_r = parse_table[:embed_r]
    
    @reference_symbol = nil
  end

  # Get a reconstructed textual representation of this parameter,
  # without indirection brackets.
  def expr_to_s
    if @value
      return REV_VALS[@value]
    end

    buf = []

    if @offset 
      buf << "0x#{@offset.to_s(16)}"
    end

    if @reference_token
      if @reference_symbol && @reference_symbol.def_instr.address
        buf << "0x#{@reference_symbol.def_instr.address.to_s(16)}"
      else
        buf << reference_token
      end
    end

    if @register
      buf << REV_REG[@register]
    end

    return buf.join("+")
  end

  # Get a reconstructed textual rep of this parameter.
  def to_s
    template = @indirect ? "[%s]" : "%s"
    return template % expr_to_s
  end

  # Does this parameter demand an additional word in the instruction?
  def needs_word?
    if @value
      return false
    end

    if @reference_token
      return true
    end
        
    if @register && @offset
      return true
    end
    
    if @offset && @offset > 0x1f
      return true
    end
  end

  # Set the reference address for the parameter
  def resolve(ref_symbol)
    @reference_symbol = ref_symbol
    ref_symbol.referenced
  end

  # Get the additional word of instruction needed, or nil if none necessary.
  def param_word
    if @reference_token
      if @reference_symbol.nil?
        raise ParseError.new("Undefined reference to: #{@reference_token}")
      end
      off = 0
      if @offset
        off += @offset
      end
      return @reference_symbol.def_instr.address + off
    end

    if @offset && needs_word?
      return @offset
    end
  end
  
  # Get the addressing mode bits. These are the 'a' or 'b' in the dcpu16 instruction.
  def mode_bits
    if @value
      return @value
    end
    
    #     register cases:
    #    0x00-0x07: register (A, B, C, X, Y, Z, I or J, in that order)
    #    0x08-0x0f: [register]
    #    0x10-0x17: [next word + register]
    if @register
      if !@indirect
        return @register #only literal register value
      end
      
      if (@offset && @offset > 0) || @reference_token #resove a label, or use a large offset
        return @register + INDIRECT_REG_NEXT_OFFSET 
      else
        return @register + INDIRECT_REG_OFFSET
      end
    end
    
    #     reference cases, with no register
    #    0x1e: [next word]
    #    0x1f: next word (literal)
    if @reference_token #we have a reference, so we'll push a word regardless
      if @indirect
        return INDIRECT_NEXT
      else
        return LITERAL_NEXT
      end
    end

    if @offset
      if @offset <= 0x1f && !@indirect
        return @offset + SHORT_LITERAL_OFFSET
      end
      
      if @indirect
        return INDIRECT_NEXT
      else
        return LITERAL_NEXT
      end
    end
    
    raise ParseError.new("Cannot build mode bits.");
  end    
end

class Instruction
  attr_reader :address, :abs_line
  attr_accessor :opcode, :a, :b, :source, :scope, :defined_symbols
  
  def initialize(source_file, global_scope, labels, parsed_line, param_a, param_b)
    @abs_line = parsed_line
    @source = source_file
    @scope = global_scope
    @defined_symbols = labels
    
    @opcode_token = @abs_line[:instr]
    @a = param_a
    @b = param_b
    
    @module = AsmSymbol::make_module_name(source_file)
    @extended = false
    
    @op = INSTRUCTIONS[@opcode_token]
    @size = 1

    if @op.nil?
      @op = EXTENDED_INSTRUCTIONS[@opcode_token]
      if @op.nil?
        puts "Unknown instruction: #{@opcode_token}"
        exit 1
      end
      @extended = true
    end

    if @a.needs_word?
      @size += 1
    end
    
    unless @extended
      if @b.needs_word?
        @size += 1
      end
    end
  end
  
  def line
    return @abs_line[:original_line]
  end

  # Fix this instruction to a particular address in the program.
  def fix(address)
    @address = address
  end

  # Build the binary representation of the entire instruction,
  # including any additional words.
  def realize
    @words = [opcode]
    if @a.needs_word?
      p_word = @a.param_word
      if p_word > 0xffff
        raise ParseError.new("Word greater than 0xfff.")
      end
      @words << p_word
    end

    if @b && @b.needs_word?
      p_word = @b.param_word
      if p_word > 0xffff
        raise ParseError.new("Word greater than 0xfff.")
      end
      @words << p_word
    end
  end

  # Get the size, in words, of the instruction.
  def size
    @size
  end

  # Get the binary words for this instruction.
  def words
    @words
  end

  # Get the opcode for this instruction.
  def opcode
    if @extended
      return 0x00 | (@op << 4) | (@a.mode_bits << 10)
    end
    return @op | (@a.mode_bits << 4) | (@b.mode_bits << 10)
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
  attr_reader :address
  attr_accessor :source, :scope, :defined_symbols

  def initialize(source_file, global_scope, labels, abstract_line)
    @abs_line = abstract_line
    @scope = global_scope
    @source = source_file
    @defined_symbols = labels
    @module = AsmSymbol::make_module_name(source_file)

    @words = []

    parse_data
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
      if @abs_line[:directive] =~ /asciz/
        @words << 0x0
      end
      return
    end
      
    if @abs_line[:directive]=~ /(word)|(uint16_t)/i
      literals = @abs_line[:directive_rem].gsub(/\s+/, '').split(",")
      literals.each do |lit|
        if lit =~ HEX_RE
          @words << $1.to_i(16)
        elsif lit =~ DEC_RE   
          @words << $1.to_i(10)
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
    #nop
  end

  def size
    return @words.size
  end

  def to_s
    labels = @defined_symbols.map{|label| ":#{label.name}"}.join("\n")
    labels << "\n" unless labels.empty?
    addr_line = @address ? "\t; [0x#{address.to_s(16)}]" : ''
    words = @words.map{|w| "\t.word 0x#{w.to_s(16)}"}
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