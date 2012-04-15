require File.expand_path(File.dirname(__FILE__) + '/abstract_asm.rb')
#indirect?
INDIRECT_RE = /\[(.*)\]/i

EMBED_R_RE = /\+?\{(.*)\}\+?/

VALUE_RE = /^(#{regex_keys(VALUES)})$/i

# Set the offset from a numeric token.
def accum_offset(token, table)
  table[:offset] = 0 unless table[:offset]
  if token =~ HEX_RE
    table[:offset] += $1.to_i(16)
  else token =~ DEC_RE
    table[:offset] += $1.to_i(10)
  end
end

# Set register from a register token.
def set_register(token, table)
  table[:register] = REGISTERS[token.downcase]
  if table[:register].nil?
    raise ParseError.new("Unknown register: #{token}")
  end
end

# Set the referenced label.
def set_reference(token, table)
  table[:reference] = token
end

def set_embed_r(token, table)
  table[:embed_r] = token
end

SPACE_PLUS = /\s+|\+|;/

# Parse the parameter expression.
def parse_param_expr(instr_hash, expr)
  ret_table = Hash.new
  if expr =~ INDIRECT_RE
    expr = $1
    ret_table[:indirect] = true
  else 
    ret_table[:indirect] = false
  end
  
  if expr.strip.start_with?('{')
    raise ParseError.new('The symbol " { " is reserved for future ruby macro support.');
  end

  #tokenize this portion.
  part = ['blah', 'blah', expr.lstrip]
  while true
    part = part[2].partition(SPACE_PLUS)
    if part[0].empty?
      break
    end

    tok = part[0]
    if tok =~ VALUE_RE
      ret_table[:value] = VALUES[tok.strip.downcase]
      break
    elsif tok =~ HEX_RE || tok =~ DEC_RE
      accum_offset(tok, ret_table)
    elsif tok =~ REGISTER_RE
      set_register(tok.strip.downcase, ret_table)
    elsif tok =~ LABEL_RE
      set_reference(tok, ret_table)
    end
  end
  return ret_table
end