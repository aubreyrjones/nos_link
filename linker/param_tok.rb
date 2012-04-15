#indirect?
INDIRECT_RE = /\[(.*)\]/i

EMBED_R_RE = /\+?\{(.*)\}\+?/


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

# Parse the parameter expression.
def parse_expression(expr)
  ret_table = Hash.new
  if expr =~ INDIRECT_RE
    expr = $1
    ret_table[:indirect] = true
  else 
    ret_table[:indirect] = false
  end

  expr.gsub!(/\s+/, '') #remove spaces
  if expr =~ VALUE_RE
    ret_table[:value] = VALUES[$1.downcase]
    return
  end

  tokens = expr.split("+")
  if tokens.nil? || tokens.size == 0
    raise  ParseError.new("No parameter given.")
  end

  tokens.each do |tok|
    if tok =~ HEX_RE || tok =~ DEC_RE
      accum_offset(tok, ret_table)
    elsif tok =~ REG_CAP_RE
      set_register($1, ret_table)
    elsif tok =~ LABEL_CAP_RE
      set_reference_label(tok, ret_table)
    elsif tok =~ EMBED_R_RE
      set_embed_r(tok, ret_table)
    else
      raise ParseError.new("Unrecognized token. #{tok}")
    end
  end
end