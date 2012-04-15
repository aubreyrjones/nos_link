

# stick consecutive name->number pairings into a hash
def declare(map, start, string)
  count = start
  string.split(" ").each do |token|
    map[token] = count
    count += 1
  end
end

INSTRUCTIONS = Hash.new
EXTENDED_INSTRUCTIONS = Hash.new
REGISTERS = Hash.new
VALUES = Hash.new

# Operational directives
DIRECTIVES = Hash.new
  
declare(INSTRUCTIONS, 1, "set add sub mul div mod shl shr and bor xor ife ifn ifg ifb")
declare(EXTENDED_INSTRUCTIONS, 1, "jsr")
declare(REGISTERS, 0, "a b c x y z i j h")
declare(VALUES, 0x18, "pop peek push sp pc o")
declare(DIRECTIVES, 0x00, '.private .hidden .word .uint16 .string .asciz .data .text')

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


class Param
  attr_accessor :offset, :reference_token, :reference_address, :register, :indirect, :embed_r

  def initialize(parse_table, instruction)
    @offset = parse_table[:offset]
    @reference_token = parse_table[:reference]
    @register = parse_table[:register]
    @indirect = parse_table[:indirect]
    @value = parse_table[:value]
    @embed_r = parse_table[:embed_r]
    @instr = instruction
    
    @reference_address = nil
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
      if @reference_address
        buf << "0x#{@reference_address.to_s(16)}"
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
  def resolve(ref_address)
    @reference_address = ref_address
  end

  # Get the additional word of instruction needed, or nil if none necessary.
  def param_word
    if @reference_token
      if @reference_address.nil?
        raise ParseError.new("Undefined reference to: #{@reference_token}", @instr)
      end
      off = 0
      if @offset
        off += @offset
      end
      return @reference_address + off
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
    
    raise ParseError.new("Cannot build mode lines.", @instr);
  end    
end

class Instruction
  attr_reader :address
  attr_accessor :opcode, :a, :b, :source, :scope, :line, :defined_symbols
  
  def initialize(source_file, global_scope, labels, opcode_token, param_a, param_b, line_number)
    @source = source_file
    @scope = global_scope
    @defined_symbols = labels
    
    @opcode_token = opcode_token
    @a = param_a
    @b = param_b
    
    @line = line_number
    
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

  # Fix this instruction to a particular address in the program.
  def fix(address)
    @address = address
  end

  # Build the binary representation of the entire instruction,
  # including any additional words.
  def realize
    @words = [opcode]
    if @a.needs_word?
      @words << @a.param_word
    end

    if @b && @b.needs_word?
      @words << @b.param_word
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
  attr_accessor :source, :scope, :line, :defined_symbols

  def initialize(source_file, global_scope, labels, value_token, line_number)
    @value_token = value_token
    @scope = global_scope
    @source = source_file
    @line = line_number
    @defined_symbols = labels
    @module = AsmSymbol::make_module_name(source_file)

    @words = []

    parse_data(@value_token)
  end

  def parse_data(token)
    if token.start_with?('"')
      raise ParseError.new("No closing quotes on string.", @instr) unless token.end_with?('"')
      
      str = token[1..-2]
      str.each_byte do |byte|
        @words << byte #this is okay, just the values
      end
    elsif token =~ HEX_RE
      @words << $1.to_i(16)
    elsif token =~ DEC_RE
      @words << $1.to_i(10)
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
    words = @words.map{|w| "\t.word 0x#{w.to_s(16)}"}.join("\n")
    return "#{labels}\t#{words}#{addr_line}"
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