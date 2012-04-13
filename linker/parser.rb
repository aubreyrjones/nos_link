require 'rubygems'

class InvalidOp < Exception
  attr_accessor :msg, :op
  def initialize(message, op)
    @msg = message
    @op = op
  end
end

class ParamError < Exception
  attr_accessor :msg, :param
  def initialize(message, param)
    @msg = message
    @param = param
  end
end

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
declare(VALUES, 0x18, "pop peek push sp pc O")

REV_REG = {}
REGISTERS.each_pair do |k, v|
  REV_REG[v] = k
end

REV_VALS = {}
VALUES.each_pair do |k, v|
  REV_VALS[v] = k
end

SECTIONS = "\\.data \\.text".split(" ")
DIRECTIVES = "\\.private \\.hidden".split(" ")
NULL_DIR = "\\.align \\.globl \\.global \\.local \\.extern".split(" ")

HEX_RE = /0x([0-9a-f]+)/i
DEC_RE = /(\d+)/

LITERAL_RE = /HEX_RE|DEC_RE/

#definition of a legal label or source symbol
LABEL_RE = /[a-z0-9\._]+/i

#Label definition
LABEL_DEF_RE = /^\s*:(#{LABEL_RE})\s*/i

# hidden global variables
HIDDEN_SYM_RE = /\.(hidden|private)\s+(#{LABEL_RE})/i

# an unsigned data word
DATA_WORD_RE = /\.(word|uint16_t)\s+(\w+)/

#an extended instruction (taking only one parameter)
EXT_INSTR_RE = /^#{LABEL_DEF_RE}?\s*(\w+)\s+(.+)$/i

SECTION_RE = /#{SECTIONS.join('|')}/

DIRECTIVE_RE = /#{DIRECTIVES.join('|')}/

NULL_DIR_RE = /#{NULL_DIR.join('|')}/

#any instruction
INSTR_RE = /#{INSTRUCTIONS.keys.join('|')}/i

# :label instruction operand, operand
LINE_RE = /#{LABEL_DEF_RE}?\s*(#{INSTR_RE})\s+(.+)\s*,\s*(.+)$/i

#registers
REGISTER_RE = /[#{REGISTERS.keys.join('')}]/i

#special parameters
VALUE_RE = /^(#{VALUES.keys.join('|')})$/i

#indirect?
INDIRECT_RE = /\[(.*)\]/i

#parameter expressions
LABEL_CAP_RE = /(#{LABEL_RE})/
REG_CAP_RE = /(#{REGISTER_RE})/

INDIRECT_REG_OFFSET = 0x08
INDIRECT_REG_NEXT_OFFSET = 0x10

INDIRECT_NEXT = 0x1e
LITERAL_NEXT = 0x1f
SHORT_LITERAL_OFFSET = 0x20

$DONT_STOP_ON_ERROR = false


def parse_error_stop(reason, source_file, line_number, line)
  puts "FATAL LINK ERROR"
  puts "Error #{reason}"
  puts "in file #{source_file} on line #{line_number}"
  puts "Errant Line: #{line}"
  exit 1 unless $DONT_STOP_ON_ERROR
end

class Param
  attr_accessor :offset, :reference_token, :reference_address, :register, :indirect

  def initialize(param_expression)
    @token = param_expression
    @offset = 0
    @reference_token = nil
    @reference_address = nil
    @register = nil
    @indirect = false
    @value = nil

    parse_expression(param_expression)
  end

  def to_s
    if @value
      return REV_VALS[@value]
    end

    buf = []

    if @offset > 0
      buf << "0x#{@offset.to_s(16)}"
    end
    if @reference_token
      buf << reference_token
    end
    if @register
      buf << REV_REG[@register]
    end
    return buf.join("+")
  end

  def needs_word?
    if !@value.nil?
      return false
    end
    return @offset > 0x1f || @reference_token
  end

  def param_word
    puts "Bullshit param word."
    return 0xffff
  end

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

      if @offset > 0 || @reference_token #resove a label, or use a large offset
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

    if @offset > 0
      if @offset <= 0x1f && !@indirect
        return @offset + SHORT_LITERAL_OFFSET
      end
      
      if @indirect
        return INDIRECT_NEXT
      else
        return LITERAL_NEXT
      end
    end

#    puts "NOPE "
#    puts @value
#    puts @register
#    puts @reference_token
#    puts @offset
#    exit 21
  end

  def set_offset(token)
    if token =~ HEX_RE
      @offset = $1.to_i(16)
    else
      @offset = $1.to_i(10)
    end
  end

  def set_register(token)
    @register = REGISTERS[token]
    if @register.nil?
      raise ParamError("Unknown register.", token)
    end
  end

  def set_reference_label(token)
    @reference_token = token
  end

  def parse_expression(expr)
    if expr =~ INDIRECT_RE
      expr = $1
      @indirect = true
    end

    expr.gsub!(/\s+/, '') #remove spaces
    if expr =~ VALUE_RE
      @value = VALUES[$1.downcase]
      puts @value
      return
    end

    tokens = expr.split("+")
    if tokens.nil? || tokens.size == 0
      raise ParamError.new("No parameter given.", expr)
    end

    tokens.each do |tok|
      if tok =~ LITERAL_RE
        set_offset(tok)
      elsif tok =~ LABEL_CAP_RE
        set_reference_label(tok)
      elsif tok =~ REG_CAP_RE
        set_register_token($1)
      else
        raise ParamError.new("Bad token.", expr)
      end
    end
  end
    
end

class Instruction
  attr_accessor :opcode, :a, :b, :source, :line, :defined_symbols
  
  def initialize(source_file, global_scope, labels, opcode_token, param_a, param_b, line_number)
    @opcode_token = opcode_token
    @scope = global_scope
    @param_a = param_a
    @param_b = param_b
    @source = source_file
    @line = line_number
    @defined_symbols = labels
    @module = AsmSymbol::make_module_name(source_file)

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

    @a = Param.new(@param_a)
    if @a.needs_word?
      @size += 1
    end
    
    @b = Param.new(@param_b)
    if @b.needs_word?
      @size += 1
    end
  end

  def size
    @size
  end

  def opcode
    @op | (@a.mode_bits << 4) | (@b.mode_bits << 10)
  end

  def to_s
    labels = @defined_symbols.map{|label| ":#{label.name}"}.join("\n")
    "#{labels}\n\t#{@opcode_token} #{@a.to_s}, #{@b.to_s}"
  end

  def orig
    "#{@op.to_s} #{@a.to_s} #{@b.to_s} : #{@labels.join("\n")} #{@opcode_token} #{@param_a}, #{@param_b}"
  end
end

class InlineData
  attr_accessor :data_words
  def initialize(module_name)
    @mod_name = module_name
    @data_words = []
  end

  def <<(data)
    @data_words << data
  end

  def length
    @data_words.size
  end

  def to_s
    @data_words.map{|word| ".word #{word.to_s}"}.join("\n")
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

  def define(instruction)
    @def_instr = instruction
  end

  def make_hidden
    @linkage_vis = :hidden
  end

  def local?
    return @linkage_vis == :local
  end

  def attach_local(local_sym)
    @dependent_locals << local_sym
  end

  def dependent_locals
    @dependent_locals
  end

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

  def self.make_local_name(parent_symbol, label)
    return "#{parent_symbol.name}$$#{label}"
  end

  def self.make_private_name(filename, name)
      return "#{make_module_name(filename)}$$#{name}"
  end

  def self.make_module_name(filename)
    filename.gsub(/^\.+/, '').gsub('/', '_')
  end
end

#Represents a single .S module file.
class ObjectModule

  attr_accessor :lines
  #Create a module from source lines.
  def initialize(file_name, source_lines)
    @filename = file_name
    @lines = source_lines
    @instructions = []
    @module_symbols = {}
    @program_symbols = {}
    @module_private_symbols = []
  end

  #Clean and normalize the source
  def normalize
    @lines.map! {|line| line.gsub(/;.*$/, '').gsub(/\s+/, ' ').strip}
  end

  #Resolve a symbol in the current tables.
  def resolve(filename, symbol_name, current_global = nil)
    if symbol_name.start_with?('.') #local label
      if current_global.nil?
        puts "Cannot locate local symbol without global context. #{filename}, #{symbol_name}"
        exit 1
      end
      resolve_name = AsmSymbol::make_local_name(current_global, symbol_name)
      return @program_symbols[resolve_name]
    else #global label
      #check for a module-private definition
      private_name = AsmSymbol::make_private_name(filename, symbol_name)
      symbol = @program_symbols[private_name]
      return symbol unless symbol.nil?
      
      #check for a global definition
      symbol = @program_symbols[symbol_name]
      return symbol
    end
  end

  def empty_line(line)
    return (line.nil? || line.empty? || line =~ /^\s+$/) #skip empty lines or whitespace lines
  end

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

  def delete_dependent_entries(table, symbol)
    symbol.dependent_locals.each do |dep|
      table.delete(dep.name)
    end
  end

  def add_dependent_entries(table, symbol)
    symbol.dependent_locals.each do |dep|
      table[dep.name] = dep
    end
  end

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

  def parse_label_pending(label_def, last_global_symbol, pending_symbols)

    retval = []
    new_local = false
    if label_def.start_with?('.')
      new_local = true
      resolved_symbol = resolve(@filename, label_def, last_global_symbol)
    else
      new_local = false
      resolved_symbol = resolve(@filename, label_def, nil)
    end
    if resolved_symbol.nil?
      puts "Resolved null symbol (#{label_def}) during parse phase. Should not happen."
      exit 1
    end

    pending_symbols << resolved_symbol
    resolved_symbol.local? ? last_global_symbol : resolved_symbol
  end

  def assemble
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

      if line =~ /^\s*#{NULL_DIR_RE}\s*/
        #null ops that we ignore
        next
      end

      if line =~ /^\s*#{LABEL_DEF_RE}\s*$/
        #this is a standalone symbol definition, save it to define it later.
        label_def = $1.strip
        last_global_symbol = parse_label_pending(label_def, last_global_symbol, pending_symbols)
        next
      end

      unless line =~ LINE_RE || line =~ EXT_INSTR_RE
        parse_error_stop("Cannot parse line.", @filename, line_number, line)
      end

      label = $1
      instruction = $2.downcase
      param_a = $3
      param_b = $4
      
      unless empty_line(label)
        label_def = $1.strip
        last_global_symbol = parse_label_pending(label_def, last_global_symbol, pending_symbols)
      end

      instr = nil
      begin
        instr = Instruction.new(@filename, last_global_symbol, pending_symbols, instruction, param_a, param_b, line_number)
      rescue ParamError => e
        parse_error_stop(e.msg, @filename, line_number, line)
      end

      pending_symbols.each do |sym|
        sym.define(instr)
      end
      pending_symbols = []
      @instructions << instr
    end
  end

  #Parse the source file into an abstract representation.
  def parse
    definitions_pass()
    mangle_and_merge
    assemble()
#    @program_symbols.each_pair do |k, sym|
#      puts "#{k} -> #{sym.def_instr.to_s}"
#    end
    
  end

  def print_listing
    outlines = @instructions.map {|ins| ins.to_s}
    puts outlines.join("\n")
  end

  def globalize_label(last_global_label, this_label, line_number, line)

    if this_label.start_with?('.') #is it a local label
      if last_global_label.nil?
        parse_error_stop("Local label without preceding global label.", @filename, line_number, line)
      end
      return [last_global_label, "#{last_global_label}$$#{this_label}"]
    end
    
    return [this_label, "#{this_label}"]
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
    om.normalize
#    puts om.lines
    om.parse
    om.print_listing
  end
end
