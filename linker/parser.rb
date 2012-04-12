class InvalidOp
  attr_accessor :msg, :op
  def initialize(message, op)
    @msg = message
    @op = op
  end
end

class ParamError
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


#definition of a legal label or source symbol
LABEL_RE = /[a-z0-9\._]+/i

#Label definition
LABEL_DEF_RE = /^\s*:(#{LABEL_RE})/i

# :label instruction operand, operand
LINE_RE = /#{LABEL_DEF_RE}?\s*(\w+)\s+(.+)\s*,\s*(.+)$/i

# hidden global variables
HIDDEN_SYM_RE = /^\.(hidden|private)\s+([a-z0-9\._]+)/i

EXT_INSTR_RE = /^(\w+)\s+(.+)$/i

HEX_RE = /^0x([0-9a-fA-F]+)$/
INT_RE = /^(\d+)$/

INSTRUCTIONS = {}
EXTENDED_INSTRUCTIONS = {}
REGISTERS = {}
VALUES = {}

declare(INSTRUCTIONS, 1, "set add sub mul div mod shl shr and bor xor ife ifn ifg ifb")
declare(EXTENDED_INSTRUCTIONS, 1, "jsr")
declare(REGISTERS, 0, "a b c x y z i j h")
declare(VALUES, 0x18, "pop peek push sp pc O")

INSTR_RE = /#{INSTRUCTIONS.keys.join('|')}/i

REGISTER_RE = /[#{REGISTERS.keys.join('')}]/i
VALUE_RE = /#{VALUES.keys.join('|')}/

INDIRECT_RE = /\[(.*)\]/i

INDIRECT_REGISTER = 0x08
INDIRECT_REG_NEXT = 0x10

NEXT_INDIRECT = 0x1e
NEXT_LITERAL = 0x1f


$DONT_STOP_ON_ERROR = false


def parse_error_stop(reason, source_file, line_number, line)
  puts "FATAL LINK ERROR"
  puts "Error #{reason}"
  puts "in file #{source_file} on line #{line_number}"
  puts "Errant Line: #{line}"
  exit 1 unless $DONT_STOP_ON_ERROR
end

class Instruction
  attr_accessor :opcode, :a, :b, :next_words, :source, :line, :defined_symbols
  
  def initialize(opcode_token, param_a, param_b, defined_symbols, source_file, line_number)
    @opcode_token = opcode_token
    @param_a = param_a
    @param_b = param_b
    @source = source_file
    @line = line_number
    @defined_symbols = defined_symbols

    @op = INSTRUCTIONS[@opcode_token]

    if @op.nil? 
      @op = EXTENDED_INSTRUCTIONS[@opcode_token]
      if @op.nil?
        puts "Unknown instruction."
        exit 1
      end
      @extended = true
    end

    @a = parse_param(@param_a)
    @b = parse_param(@param_b) unless @extended

    @next_words = []
  end

  def parse_param(param_token)
    indirect = param_token =~ INDIRECT_RE
    if indirect
      param_token = $1.strip
    end
    
    if param_token =~ REGISTER_RE #it's a register
      reg_code = REGISTERS[$1]
      return REGISTERS[$1] + (indirect ? INDIRECT_REGISTER : 0)
    elsif param_token =~ VALUE_RE #it's one of the special magic values
      if indirect
        raise ParamError.new("#{param_token} cannot be used for indirection.", param_token)
      end
      return VALUES[param_token]
    end

    puts "Don't know how to handle: #{param_token}"

    return -1
  end

  def orig
    "#{@op.to_s} #{@a.to_s} #{@b.to_s} : #{@labels.join("\n")} #{@opcode_token} #{@param_a}, #{@param_b}"
  end
end

class InlineData
  attr_accessor :data_words
  def initialize
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
    if label.start_with?('.') #local label
      if current_global.nil?
        puts "Cannot locate local symbol without global context."
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
      if line =~ LABEL_DEF_RE || line =~ LINE_RE
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
      table.delete(dep)
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

  def assemble

    pending_symbols = []
    last_global_symbol = nil #might also be hidden

    @lines.each_with_index do |line, line_number|

      if line.empty? || line =~ /^\s+$/ #skip empty lines or whitespace lines
        next
      end

      if line =~ LABEL_DEF_RE #this is a standalone symbol definition
        
      end

      unless line =~ LINE_RE || line =~ EXT_INSTR_RE
        parse_error_stop("Cannot parse line.", @filename, line_number, line)
      end

      label = $1
      instruction = $2.downcase
      param_a = $3
      param_b = $4
      
      unless label.nil? || label.empty?
        last_global_label, label = globalize_label(last_global_label, label, line_number, line)
        pending_labels << label
      end
      begin
        instr = Instruction.new(instruction, param_a, param_b, pending_labels, @filename, line_number)
        pending_labels = []
        puts instr.orig
      rescue ParamError => e
        parse_error_stop(e.msg, @filename, line_number, line)
      end
    end
  end

  #Parse the source file into an abstract representation.
  def parse
    definitions_pass()
    mangle_and_merge
    puts "Symbol table:"
    @program_symbols.each_key do |k|
      puts k
    end
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
  end
end
