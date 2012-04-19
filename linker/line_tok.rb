require_relative 'abstract_asm.rb'

SPACE = /\s+/i
KILL_COMMENT = /(;.*$)/i

require File.expand_path(File.dirname(__FILE__) + '/param_tok.rb')

# Todo: this needs to handle inline ruby macros, which means no naive split on ','.
def parse_instruction_line(ret_table, instr_tok, line_rem)
  param_toks = line_rem.split(',')
  
  if param_toks.nil? || param_toks.size == 0
      raise ParseError.new("No parameters given for instruction '#{instr_tok}'.")
  end
  
  if param_toks.size > 0
    ret_table[:a_token] = param_toks[0]
    ret_table[:param_a] = parse_param_expr(ret_table, param_toks[0]) 
  end
  
  if param_toks.size > 1
    ret_table[:b_token] = param_toks[1]
    ret_table[:param_b] = parse_param_expr(ret_table, param_toks[1])
  end
end


def tokenize_line(filename, line_no, line_str)
  ret_table = Hash.new
  ret_table[:original_line] = line_str
  ret_table[:line_number] = line_no
    
  part = ['blah', 'blah', line_str.gsub(KILL_COMMENT, '').strip!]
  while true
    part = part[2].partition(SPACE)
    if part[0].empty?
      break
    end
    
    if part[0].start_with?(';')
      ret_table[:comment] = part[2]
      break
    end
    
    token = part[0]
    
    if token =~ LABEL_DEF
      raise ParseError.new("Parse error, redundant label definition.") if ret_table[:label]
      label = token.gsub(':', '').strip
      ret_table[:label] = label
      ret_table[:label_local] = label.start_with?('.')
      next
    elsif token =~ INSTR_RE
      ret_table[:instr] = token.downcase
      ret_table[:instr_rem] = part[2]
      parse_instruction_line(ret_table, ret_table[:instr], ret_table[:instr_rem])
      break
    elsif token =~ DIRECT_RE
      ret_table[:directive] = token.downcase
      ret_table[:directive_rem] = part[2]
      break
    elsif token.start_with?('.')
      unless token =~ NULL_DIR_RE
        parse_warning(filename, line_no, line_str, "Unknown directive '#{token}'.")
      end
      ret_table[:unknown_directive] = token.downcase
      ret_table[:unknown_directive_rem] = part[2]
      break
    else
      raise ParseError.new("Bad token: #{token}.")
    end
  end

  return ret_table
end
