require_relative 'abstract_asm.rb'
#indirect?
INDIRECT_RE = /\[(.*)\]/i

EMBED_R_RE = /\+?\{(.*)\}\+?/

VALUE_RE = /^(#{regex_keys(VALUES)})$/i

def parse_literal(token, separated_sign = nil)
  sign = 1
  
  if separated_sign.nil?
    if token.start_with?('+')
      token = token[1..-1]
    elsif token.start_with?('-')
      sign *= -1
      token = token[1..-1]
    end
  else
    if separated_sign == '+'
      #nop
    elsif separated_Sign == '-'
      sign *= -1
    end
  end
  
  
  base = 10
  to_i_token = token
  begin
    if token.downcase.start_with?('0x')
      base = 16
      return token[2..-1].to_i(16) * sign
    end

    return to_i_token.to_i(10) * sign
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
def parse_param_expr(expr)
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
  current_sign = false
  part = ['blah', 'blah', expr.lstrip]
  while true
    part = part[2].partition(SPACE_PLUS_MINUS)
    
    unless part[1] =~ /^\s*$/
      current_sign = part[1]
    end
    
    if part[0].empty?
      if part[2].empty?
        break
      end
      next
    end

    tok = part[0]
    
    if tok =~ HEX_RE || tok =~ DEC_RE
      accum_offset(ret_table, parse_literal(tok, current_sign))
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