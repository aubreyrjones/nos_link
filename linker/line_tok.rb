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
declare(DIRECTIVES, 0x00, '.private .hidden .word .uint16 .string .asciz .data .text ')

REV_REG = {}
REGISTERS.each_pair do |k, v|
  REV_REG[v] = k
end

REV_VALS = {}
VALUES.each_pair do |k, v|
  REV_VALS[v] = k
end

def regex_keys(h)
  return /(#{h.keys.join(")|(")})/
end 

HEX_RE = /^0x([0-9a-f]+)$/i
DEC_RE = /^(\d+)$/

#definition of a legal label or source symbol
LABEL_RE = /[\._a-z]+[a-z0-9\._]+/i

#label definition token
LABEL_DEF = /(:#{LABEL_RE})|(#{LABEL_RE}:)/i

#instruction token
INSTR_RE = /#{regex_keys(INSTRUCTIONS)}|#{regex_keys(EXTENDED_INSTRUCTIONS)}/i

#Directive tokens
DIRECT_RE = /#{regex_keys(DIRECTIVES)}/i

SPACE = /\s+/i

def parse_warning(filename, line_no, line_str, msg)
  puts "Parse Warning: #{msg}"
  puts "\tin #{filename}, line #{line_no}"
end

class ParseError < Exception
  attr_accessor :msg
  def initialize(msg)
    @msg = msg
  end
end

def parse_instruction_line(ret_table, instr_tok, line_rem)
  param_toks = line_rem.split(',')
  
  if tokens.nil? || tokens.size == 0
      raise ParseError.new("No parameters given for instruction '#{instr_tok}'.")
  end
  
  if param_toks.size > 0
    ret_table[:a_token] = param_toks[0]
  end
  
  if param_toks.size > 1
    ret_table[:b_token] = param_toks[1]
  end
end

# It is assumed that the line is normalized.
# Specifically : @lines.map! {|line| line.gsub(/;.*$/, '').gsub(/\s+/, ' ').strip}
# So, no comments, all multispaces are replaced with single. And leading/trailing space is removed
def tokenize_line(filename, line_no, line_str)
  ret_table = Hash.new
  part = ['blah', 'blah', line_str]
  while true
    part = part[2].partition(SPACE)
    if part[0].empty?
      break
    end
    
    token = part[0]
    
    if token =~ LABEL_DEF
      raise ParseError.new("Parse error, redundant label definition.") if ret_table[:label]
      label = token
      label.gsub!(':', '').strip!()
      ret_table[:label] = label
      next
    elsif token =~ INSTR_RE
      ret_table[:instr_token] = token.downcase
      ret_table[:instr_rem] = part[2]
    elsif token =~ DIRECT_RE
      ret_table[:directive_token] = token.downcase
      ret_table[:directive_rem] = part[2]
      return
    elsif token.start_with?('.')
      parse_warning(filename, line_no, line_str, "Unknown directive '#{token}'.")
    else
      raise ParseError.new("Unknown parse error.")
    end
  end
end
