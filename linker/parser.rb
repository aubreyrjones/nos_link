def declare(map, start, string)
  count = start
  string.split(" ").each do |token|
    map[token] = count
    count += 1
  end
end

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

REGISTER_RE = /^([#{REGISTERS.keys.join('')}])$/
INDIRECT_RE = /\[(.*)\]/

VALUE_RE = /^(#{VALUES.keys.join('|')})$/

INDIRECT_REGISTER = 0x08
INDIRECT_REG_NEXT = 0x10

NEXT_INDIRECT = 0x1e
NEXT_LITERAL = 0x1f


$DONT_STOP_ON_ERROR = false

class ParamError
  attr_accessor :msg, :param
  def initialize(message, param)
    @msg = message
    @param = param
  end
end

def parse_error_stop(reason, source_file, line_number, line)
  puts "FATAL LINK ERROR"
  puts "Error #{reason}"
  puts "in file #{source_file} on line #{line_number}"
  puts "Errant Line: #{line}"
  exit 1 unless $DONT_STOP_ON_ERROR
end

class Instruction
  attr_accessor :opcode, :a, :b, :next_words, :source, :line
  
  def initialize(opcode_token, param_a, param_b, labels, source_file, line_number)
    @opcode_token = opcode_token
    @param_a = param_a
    @param_b = param_b
    @source = source_file
    @line = line_number
    @labels = labels

    @op = INSTRUCTIONS[@opcode_token]

    if @op.nil? 
      @op = EXTENDED_INSTRUCTIONS[@opcode_token]
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

class DataWords
  
end

#Represents a single .S module file.
class ObjectModule

  #Label on a line by itself
  LABEL_RE = /^:([a-zA-Z0-9\._]+)/
  # :label instruction operand, operand
  LINE_RE = /^\s*(:[a-zA-Z0-9\._]+|\s*)(\w+)\s+(.+)\s*,\s*(.+)$/

  EXT_INSTR_RE = /^(:[a-zA-Z0-9\._]+|\s*)(\w+)\s+(.+)$/

  attr_accessor :lines
  #Create a module from source lines.
  def initialize(file_name, source_lines)
    @filename = file_name
    @lines = source_lines
    @instructions = []
    @defined_symbols = {}
  end

  #Clean and normalize the source
  def normalize
    @lines.map! {|line| line.gsub(/;.*/, '').gsub(/\s+/, ' ').strip.downcase}
  end
  
  #Parse the source file into an abstract representation.
  def parse
    last_global_label = nil
    pending_labels = []

    @lines.each_with_index do |line, line_number|

      if line.empty? || line =~ /^\s+$/ #skip empty lines or whitespace lines
        next
      end

      if line =~ LABEL_RE #this is a standalone label and must be saved
        label = $1
        last_global_label, label = globalize_label(last_global_label, label, line_number, line)
        pending_labels << label
        next #next line please!
      end

      unless line =~ LINE_RE || line =~ EXT_INSTR_RE
        parse_error_stop("Cannot parse line.", @filename, line_number, line)
      end

      label = $1
      instruction = $2
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
