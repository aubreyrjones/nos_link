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



class Instruction
  attr_accessor :opcode, :a, :b, :a_word, :b_word
  
  def initialize(opcode_token, param_a, param_b)
    
  end


end

#Represents a single .S module file.
class ObjectModule

  LABEL_RE = /^\s*:([a-zA-Z0-9\._]+)/
  LINE_RE = /^\s*(:[a-zA-Z0-9\._]+|\s+)(\w+)\s+(.+)\s*,\s*(.+)/
                 #label                #instruction #operand tokens



  #Create a module from source lines.
  def initialize(source_lines)
    @lines = source_lines
    @instructions = []

    normalize
    @lines.each do |line|
      parse_line(line)
    end
  end

  #Clean and normalize the source
  def normalize
    @lines.map! {|line| line.gsub(/;.*/, '').gsub(/\s+/, ' ').strip.downcase}
    @lines.reject! {|line| line.empty?}
  end

  #parse lines into insructions
  def parse_line(line)
    
  end

end

if __FILE__ == $PROGRAM_NAME
  filename = "#{ARGV.first || "out.s"}"
  open(filename, 'r') do |file|
    ObjectModule.new(file.readlines)
  end
end
