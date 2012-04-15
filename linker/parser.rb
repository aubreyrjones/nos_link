require 'rubygems'
require File.expand_path(File.dirname(__FILE__) + '/resolve.rb')

class ParseError < Exception
  attr_accessor :msg, :instr
  def initialize(message, errant_instruction)
    @msg = message
    @instr = errant_instruction
  end
end

# stick consecutive name->number pairings into a hash
def declare(map, start, string)
  count = start
  string.split(" ").each do |token|
    map[token] = count
    count += 1
  end
end



INSTRUCTIONS = {}
EXTENDED_INSTRUCTIONS = {}
REGISTERS = {}
VALUES = {}

declare(INSTRUCTIONS, 1, "set add sub mul div mod shl shr and bor xor ife ifn ifg ifb")
declare(EXTENDED_INSTRUCTIONS, 1, "jsr")
declare(REGISTERS, 0, "a b c x y z i j h")
declare(VALUES, 0x18, "pop peek push sp pc o")

REV_REG = {}
REGISTERS.each_pair do |k, v|
  REV_REG[v] = k
end

REV_VALS = {}
VALUES.each_pair do |k, v|
  REV_VALS[v] = k
end

# Legal sections
SECTIONS = "\\.data \\.text".split(" ")

# Legal directives
DIRECTIVES = "\\.private \\.hidden".split(" ")

# Null directives (skipped)
NULL_DIR = "\\.section \\.file \\.align \\.globl \\.global \\.local \\.extern".split(" ")

HEX_RE = /^0x([0-9a-f]+)$/i
DEC_RE = /^(\d+)$/

#definition of a legal label or source symbol
LABEL_RE = /[\._a-z]+[a-z0-9\._]+/i

#Label definition
LABEL_DEF_RE = /^\s*:(#{LABEL_RE})\s*/i

# hidden global variables
HIDDEN_SYM_RE = /\.(hidden|private)\s+(#{LABEL_RE})/i

# an unsigned data word
DATA_WORD_RE = /\.(word|uint16_t)/

#an extended instruction (taking only one parameter)
EXT_INSTR_RE = /^#{LABEL_DEF_RE}?\s+(\w+)\s+(.+)$/i

SECTION_RE = /#{SECTIONS.join('|')}/

DIRECTIVE_RE = /#{DIRECTIVES.join('|')}/

NULL_DIR_RE = /#{NULL_DIR.join('|')}/

#any instruction
INSTR_RE = /#{INSTRUCTIONS.keys.join('|')}/i

ONE_PARAM_OPS = [].concat(EXTENDED_INSTRUCTIONS.keys)
ONE_PARAM_OPS << '.word' << '.uint16_t'

STRING_LINE = /#{LABEL_DEF_RE}?\s*(\.string|\.asciz)\s+(".*")$/i

ONE_PARAM_LINE = /#{LABEL_DEF_RE}?\s*(#{ONE_PARAM_OPS.join('|')})\s+([^,]+)\s*$/i

# :label instruction operand, operand
TWO_PARAM_LINE = /#{LABEL_DEF_RE}?\s*(#{INSTR_RE})\s+(.+)\s*,\s*(.+)$/i

#registers
REGISTER_RE = /[#{REGISTERS.keys.join('')}]/i

#special parameters
VALUE_RE = /^(#{VALUES.keys.join('|')})$/i

#indirect?
INDIRECT_RE = /\[(.*)\]/i

#parameter expressions
LABEL_CAP_RE = /(#{LABEL_RE})/
REG_CAP_RE = /^(#{REGISTER_RE})$/

INDIRECT_REG_OFFSET = 0x08
INDIRECT_REG_NEXT_OFFSET = 0x10

INDIRECT_NEXT = 0x1e
LITERAL_NEXT = 0x1f
SHORT_LITERAL_OFFSET = 0x20

$DONT_STOP_ON_ERROR = false


def parse_error_stop(reason, source_file, line_number, line)
  puts "FATAL LINK ERROR"
  puts "Error: #{reason}"
  puts "in file #{source_file} on line #{line_number + 1}"
  puts "Errant Line: #{line}"
  raise Exception.new if $config[:hacking]
  exit 1 unless $DONT_STOP_ON_ERROR
end

class Param
  attr_accessor :offset, :reference_token, :reference_address, :register, :indirect

  def initialize(param_expression, instruction)
    @token = param_expression
    @offset = nil
    @reference_token = nil
    @reference_address = nil
    @register = nil
    @indirect = false
    @value = nil
    @instr = instruction

    parse_expression(param_expression)
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
  
  # Set the offset from a numeric token.
  def set_offset(token)
    if token =~ HEX_RE
      @offset = $1.to_i(16)
    else token =~ DEC_RE
      @offset = $1.to_i(10)
    end
  end

  # Set register from a register token.
  def set_register(token)
    @register = REGISTERS[token.downcase]
    if @register.nil?
      raise ParseError.new("Unknown register.", @instr)
    end
  end

  # Set the referenced label.
  def set_reference_label(token)
    @reference_token = token
  end

  # Parse the parameter expression.
  def parse_expression(expr)
    if expr =~ INDIRECT_RE
      expr = $1
      @indirect = true
    end

    expr.gsub!(/\s+/, '') #remove spaces
    if expr =~ VALUE_RE
      @value = VALUES[$1.downcase]
      return
    end

    tokens = expr.split("+")
    if tokens.nil? || tokens.size == 0
      raise  ParseError.new("No parameter given.", @instr)
    end

    tokens.each do |tok|
      if tok =~ HEX_RE || tok =~ DEC_RE
        set_offset(tok)
      elsif tok =~ REG_CAP_RE
        set_register($1)
      elsif tok =~ LABEL_CAP_RE
        set_reference_label(tok)
      else
        puts tok
        raise ParseError.new("Unrecognized token.", @instr)
      end
    end
  end
    
end

class Instruction
  attr_reader :address
  attr_accessor :opcode, :a, :b, :source, :scope, :line, :defined_symbols
  
  def initialize(source_file, global_scope, labels, opcode_token, param_a, param_b, line_number)
    @opcode_token = opcode_token
    @scope = global_scope
    @param_a = param_a
    @param_b = param_b
    @source = source_file
    @line = line_number
    @defined_symbols = labels
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
    
    @a = Param.new(@param_a, self)
    if @a.needs_word?
      @size += 1
    end
    
    unless @extended
      @b = Param.new(@param_b, self)
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

#Represents a single .S module file.
class ObjectModule
  attr_reader :filename, :lines
  attr_accessor :instructions, :module_symbols, :program_symbols


  # Create a module from source lines.
  def initialize(file_name, source_lines)
    @filename = file_name
    @lines = source_lines
    @instructions = []
    @module_symbols = {}
    @program_symbols = {}
    @module_private_symbols = []
  end

  # Clean and normalize the source
  def normalize
    @lines.map! {|line| line.gsub(/;.*$/, '').gsub(/\s+/, ' ').strip}
  end

  # Is this line empty?
  def empty_line(line)
    return (line.nil? || line.empty? || line =~ /^\s+$/) #skip empty lines or whitespace lines
  end

  # Extract all symbols *defined* by this module.
  # References are not handled at this stage.
  def definitions_pass
    last_global_symbol = nil
    @lines.each_with_index do |line, line_number|
      next if empty_line(line)
      if line =~ LABEL_DEF_RE
        if empty_line($1)
          next
        end
        label = $1.strip
        parent = nil
        if label.start_with?('.')
          parent = last_global_symbol
        end
        defined_symbol = AsmSymbol.new(@filename, label, parent)
        @module_symbols[defined_symbol.name] = defined_symbol
        if parent.nil? #it's a global
          last_global_symbol = defined_symbol
        else #it's a local, attach dependency.
          last_global_symbol.attach_local(defined_symbol) 
        end

      elsif line =~ HIDDEN_SYM_RE
        hidden_symbol = $2
        @module_private_symbols << hidden_symbol
      end
    end
  end

  # Remove all dependent entires of symbol from the table.
  def delete_dependent_entries(table, symbol)
    symbol.dependent_locals.each do |dep|
      table.delete(dep.name)
    end
  end

  # Add all dependent entries of the symbol to this table.
  def add_dependent_entries(table, symbol)
    symbol.dependent_locals.each do |dep|
      table[dep.name] = dep
    end
  end

  # Mangle all local and private names, and merge them into
  # the program symbol table.
  def mangle_and_merge
    #mangle the private names
    @module_private_symbols.each do |symbol_name|
      symbol = @module_symbols[symbol_name]
      if symbol.nil?
        puts "Warning: Setting visibility of undefined symbol: #{symbol_name}. Skipping."
        next
      end
      old_name = symbol.name
      @module_symbols.delete(old_name)
      delete_dependent_entries(@module_symbols, symbol)
      symbol.make_hidden
      add_dependent_entries(@module_symbols, symbol)
      @module_symbols[symbol.name] = symbol
    end

    #next step: merge upward to the program scope.
    @module_symbols.each_pair do |name, sym|
      existing_def = @program_symbols[name]
      if existing_def.nil?
        @program_symbols[name] = sym
        next
      end
      if existing_def.is_defined?
        puts "Warning: Attempting to redefine symbol #{name}. Skipping redefinition."
        next
      end
    end
  end


  # Used to define instructions, this function looks up the symbol corresponding
  # to the given label_def according to resolution rules. It appends the located
  # symbol to pending_symbols.
  #
  # If the resolved symbol is not local, then it is returned as the last global symbol.
  # Otherwise, if the resolved symbol is local, then the given last_global_symbol
  # will be returned.
  def parse_label_pending(label_def, last_global_symbol, pending_symbols)
    retval = []
    new_local = false
    if label_def.start_with?('.')
      new_local = true
      resolved_symbol = resolve(@program_symbols, @filename, label_def, last_global_symbol)
    else
      new_local = false
      resolved_symbol = resolve(@program_symbols, @filename, label_def, nil)
    end
    if resolved_symbol.nil?
      puts "Resolved null symbol (#{label_def}) during parse phase. Should not happen."
      exit 1
    end

    pending_symbols << resolved_symbol
    return resolved_symbol.local? ? last_global_symbol : resolved_symbol
  end

  # Do the main pass through the code, implementing symbols and parsing instructions.
  def do_main_pass
    pending_symbols = []
    last_global_symbol = nil #might also be hidden
    current_section = :text


    @lines.each_with_index do |line, line_number|
      if empty_line(line)
        next
      end

      if line =~ HIDDEN_SYM_RE 
        #already used by the definitions phase
        next
      end

      if line =~ /^\s*(#{SECTION_RE})\s*$/
        case $1
        when '.text'
          current_section = :text
        when '.data'
          current_section = :data
        end

        next
      end

      if line =~ /^\s*(#{DIRECTIVE_RE})/
        #only visibility at the moment, skip
        next
      end

      if line =~ /^\s*(#{NULL_DIR_RE})/
        #null ops that we ignore
        next
      end

      if line =~ /^\s*#{LABEL_DEF_RE}\s*$/
        #this is a standalone symbol definition, save it to define it later.
        label_def = $1.strip
        last_global_symbol = parse_label_pending(label_def, last_global_symbol, pending_symbols)
        next
      end

#      debugger
      unless line =~ STRING_LINE || line =~ TWO_PARAM_LINE || line =~ ONE_PARAM_LINE
        parse_error_stop("Cannot parse line.", @filename, line_number, line)
      end

      label = $1
      instruction = $2.downcase
      param_a = $3
      param_b = $4
      
      param_a.strip if param_a
      param_b.strip if param_b

      unless empty_line(label)
        label_def = label.strip
        last_global_symbol = parse_label_pending(label_def, last_global_symbol, pending_symbols)
      end

      instr = nil

      if instruction =~ DATA_WORD_RE || instruction.strip =~ /\.string|\.asciz/i
        begin
          instr = InlineData.new(@filename, last_global_symbol, pending_symbols, param_a, line_number)
        rescue ParseError => e
          parse_error_stop(e.msg, @filename, line_number, line)
        end
      else #try to parse as regular instruction
        
        begin
          instr = Instruction.new(@filename, last_global_symbol, pending_symbols, instruction, param_a, param_b, line_number)
        rescue ParseError => e
          parse_error_stop(e.msg, @filename, line_number, line)
        end
      end

      pending_symbols.each do |sym|
        sym.define(instr)
      end
      pending_symbols = []
      @instructions << instr
    end
  end

  # Parse the source file into an abstract representation.
  def parse
    normalize()
    definitions_pass()
    mangle_and_merge()
    do_main_pass()
  end

  # Print a listing of this module.
  def print_listing
    outlines = @instructions.map {|ins| ins.to_s}
    puts outlines.join("\n")
  end
end

# $DONT_STOP_ON_ERROR = true

if __FILE__ == $PROGRAM_NAME
  filename = "#{ARGV.first || "out.s"}"
  om = nil
  open(filename, 'r') do |file|
    om = ObjectModule.new(filename, file.readlines)
  end
  
  unless om.nil?
    om.parse
    om.print_listing
  end
end
