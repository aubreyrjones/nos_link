require File.expand_path(File.dirname(__FILE__) + '/abstract_asm.rb')
#indirect?
INDIRECT_RE = /\[(.*)\]/i

EMBED_R_RE = /\+?\{(.*)\}\+?/

VALUE_RE = /^(#{regex_keys(VALUES)})$/i

def parse_literal(token, should_negate)
  sign = should_negate ? -1 : 1
  base = 10
  to_i_token = token
  begin
    if token.downcase.start_with?('0x')
      base = 16
      return token[2..-1].to_i(16) * sign
    end

    return to_i_token.to_i(base) * sign
  rescue 
    raise ParseError("Cannot parse numeric literal '#{token}'.")
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

SPACE_PLUS_MINUS = /\s+|\+|-|;/

def accum_offset(ret_table, value)
  ret_table[:offset] = 0 unless ret_table[:offset]
  ret_table[:offset] += value
end

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
  negate_next = false
  part = ['blah', 'blah', expr.lstrip]
  while true
    part = part[2].partition(SPACE_PLUS_MINUS)
    
    if part[1] == '-'
      negate_next = !negate_next
    end 
    
    if part[0].empty?
      if part[2].empty?
        break
      end
      next
    end

    tok = part[0]
    
    if tok =~ /^\d/
      accum_offset(ret_table, parse_literal(tok, negate_next))
      should_negate = false
      next
    end
    
    if should_negate
      raise ParseError("Token '#{tok}' cannot be negative. Only numeric literals (hex or dec) may be negative.")
    end
    
    if tok =~ VALUE_RE
      ret_table[:value] = VALUES[tok.strip.downcase]
      break
    elsif tok =~ REGISTER_RE
      set_register(tok.strip.downcase, ret_table)
    elsif tok =~ LABEL_RE
      set_reference(tok, ret_table)
    end
  end
  return ret_table
end