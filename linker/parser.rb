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
declare(REGISTERS, 0, "a b c x y z i h")
declare(VALUES, 0x18, "pop peek push sp pc O")

INDIRECT_OFFSET = 0x08
INDIRECT_NEXT = 0x1e
NEXT_LITERAL = 0x1f
SHORT_LITERAL = 0x20

$DONT_STOP_ON_ERROR = false

def parse_error_stop(reason, source_file, line_number, line)
  puts "FATAL LINK ERROR"
  puts "Error #{reason}"
  puts "in file #{source_file} on line #{line_number}"
  puts "Errant Line: #{line}"
  exit 1 unless $DONT_STOP_ON_ERROR
end

class Instruction
  attr_accessor :opcode, :a, :b, :a_word, :b_word, :source, :line
  
  def initialize(opcode_token, param_a, param_b, labels, source_file, line_number)
    @opcode_token = opcode_token
    @param_a = param_a
    @param_b = param_b
    @sourece = source_file
    @line = line_number
    @labels = labels
  end

  def orig
    "#{@labels.join("\n")} #{@opcode_token} #{@param_a}, #{@param_b}"
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
      
      instr = Instruction.new(instruction, param_a, param_b, pending_labels, @filename, line_number)
      pending_labels = []
      puts instr.orig
    
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

$DONT_STOP_ON_ERROR = true

if __FILE__ == $PROGRAM_NAME
  filename = "#{ARGV.first || "out.s"}"
  om = nil
  open(filename, 'r') do |file|
    om = ObjectModule.new(filename, file.readlines)
  end

  unless om.nil?
    om.normalize
    om.parse
  end
end
