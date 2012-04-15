require File.expand_path(File.dirname(__FILE__) + '/abstract_asm.rb')

def regex_keys(h)
  return /(#{h.keys.join(")|(")})/i
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

require File.expand_path(File.dirname(__FILE__) + '/param_tok.rb')


def parse_instruction_line(ret_table, instr_tok, line_rem)
  param_toks = line_rem.split(',')
  
  if tokens.nil? || tokens.size == 0
      raise ParseError.new("No parameters given for instruction '#{instr_tok}'.")
  end
  
  if param_toks.size > 0
    ret_table[:a_token] = param_toks[0]
    ret_table[:a_param] = parse_param_expr(param_toks[0]) 
  end
  
  if param_toks.size > 1
    ret_table[:b_token] = param_toks[1]
    ret_table[:b_param] = parse_param_expr(param_toks[0])
  end
end

# It is assumed that the line is normalized.
# Specifically : @lines.map! {|line| line.gsub(/;.*$/, '').gsub(/\s+/, ' ').strip}
# So, no comments, all multispaces are replaced with single. And leading/trailing space is removed
def tokenize_line(filename, line_no, line_str)
  ret_table = Hash.new
  ret_table[:original_line] = line_str
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
      ret_table[:instr] = token.downcase
      ret_table[:instr_rem] = part[2]
      break
    elsif token =~ DIRECT_RE
      ret_table[:directive] = token.downcase
      ret_table[:directive_rem] = part[2]
      break
    elsif token.start_with?('.')
      parse_warning(filename, line_no, line_str, "Unknown directive '#{token}'.")
      ret_table[:unknown_directive] = token.downcase
      ret_table[:unknown_directive_rem] = part[2]
      break
    else
      raise ParseError.new("Bad token: #{token}.")
    end
  end

  return ret_table
end
