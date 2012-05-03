require_relative 'abstract_asm.rb'
require_relative 'resolve.rb'
require_relative 'line_tok.rb'

$DONT_STOP_ON_ERROR = false

unless $config
  $config = {}
  $config[:hacking] = true
end

def parse_error_stop(e, source_file, line_number, line)
  puts "FATAL PARSE ERROR"
  puts "Error: #{e.msg}"
  puts "in file #{source_file} on line #{line_number + 1}"
  puts "Errant Line: #{line}"
  puts e.backtrace if $config[:hacking]
  exit 1 unless $DONT_STOP_ON_ERROR
end

class CompactObjectModule
end

#Represents a single .S module file.
class ObjectModule
  attr_reader :filename, :lines, :parse_tree
  attr_accessor :instructions, :module_symbols, :program_symbols, :functions


  # Create a module from source lines.
  def initialize(file_name, source_lines)
    @filename = file_name
    @lines = source_lines
    @instructions = []
    @module_symbols = {}
    @program_symbols = {}
    @module_private_symbols = []
    @functions = {}
    @parse_tree = []
  end

  # Is this line empty?
  def empty_line(line)
    return (line.nil? || line.empty? || line =~ /^\s+$/) #skip empty lines or whitespace lines
  end

  # Extract all symbols *defined* by this module.
  # References are not handled at this stage.
  def definitions_pass
    last_global_symbol = nil
    @parse_tree.each do |abs_line|
      if abs_line[:directive] =~ /(\.hidden)|(\.private)/i
        @module_private_symbols << abs_line[:directive_rem].strip
        next
      end
      
      next unless abs_line[:label]
      
      parent = nil
      if abs_line[:label_local]
        parent = last_global_symbol
      end
      defined_symbol = AsmSymbol.new(@filename, abs_line[:label], parent)
      
      @module_symbols[defined_symbol.name] = defined_symbol
      
      if parent.nil? #it's a global
        last_global_symbol = defined_symbol
      else #it's a local, attach dependency.
        last_global_symbol.attach_local(defined_symbol) 
      end
    end
  end

  # Remove all dependent entires of symbol from the table.
  def delete_dependent_entries(table, symbol)
    symbol.dependent_locals.each do |dep|
      table.delete(dep.name)
    end
  end

  # Add all dependent entries of the symbol to this table.
  def add_dependent_entries(table, symbol)
    symbol.dependent_locals.each do |dep|
      table[dep.name] = dep
    end
  end

  # Mangle all local and private names, and merge them into
  # the program symbol table.
  def mangle_and_merge
    #mangle the private names
    @module_private_symbols.each do |symbol_name|
      symbol = @module_symbols[symbol_name]
      if symbol.nil?
        puts "Warning: Setting visibility of undefined symbol: #{symbol_name}. Skipping."
        next
      end
      old_name = symbol.name
      @module_symbols.delete(old_name)
      delete_dependent_entries(@module_symbols, symbol)
      symbol.make_hidden
      add_dependent_entries(@module_symbols, symbol)
      @module_symbols[symbol.name] = symbol
    end

    #next step: merge upward to the program scope.
    @module_symbols.each_pair do |name, sym|
      existing_def = @program_symbols[name]
      if existing_def.nil?
        @program_symbols[name] = sym
        next
      end
      if existing_def.is_defined?
        puts "Warning: Attempting to redefine symbol #{name}. Skipping redefinition."
        next
      end
    end
  end


  # Used to define instructions, this function looks up the symbol corresponding
  # to the given label_def according to resolution rules. It appends the located
  # symbol to pending_symbols.
  #
  # If the resolved symbol is not local, then it is returned as the last global symbol.
  # Otherwise, if the resolved symbol is local, then the given last_global_symbol
  # will be returned.
  def parse_label_pending(abs_line, last_global_symbol, pending_symbols)
    new_local = false
    if abs_line[:label_local]
      new_local = true
      resolved_symbol = resolve(@program_symbols, @filename, abs_line[:label], last_global_symbol)
    else
      new_local = false
      resolved_symbol = resolve(@program_symbols, @filename, abs_line[:label], nil)
    end
    if resolved_symbol.nil?
      puts "Resolved null symbol (#{abs_line[:label]}) during parse phase. Should not happen."
      exit 1
    end

    pending_symbols << resolved_symbol
    return resolved_symbol.local? ? last_global_symbol : resolved_symbol
  end

  # Do the main pass through the code, implementing symbols and parsing instructions.
  def do_main_pass
    pending_symbols = []
    last_global_symbol = nil #might also be hidden
    current_section = :text
    
    @parse_tree.each do |abs_line|
      
      if abs_line[:label] #stack up labels
        last_global_symbol = parse_label_pending(abs_line, last_global_symbol, pending_symbols)
      end
      
      if abs_line[:instr]
        instr_clz = nil
        if DATA_DIRECTIVES.has_key?(abs_line[:instr])
          instr_clz = InlineData
        elsif ALL_INSTR.has_key?(abs_line[:instr])
          instr_clz = Op
        else
          puts "Unknown token #{abs_line[:instr]}"
          raise ParseError.new("Unknown instruction #{abs_line[:instr]}")
        end
        
        # require 'ruby-debug/debugger'
        
        instr = instr_clz.new(@filename, 
                                last_global_symbol, 
                                pending_symbols, 
                                abs_line)
        define_and_push(instr, pending_symbols)
        pending_symbols = []
      end
    end
  end
  
  def define_and_push(instr, pending_symbols)
    pending_symbols.each do |sym|
      sym.define(instr)
    end

    instr.params.each do |p|
      next unless p.is_a? Param
      p.rewrite_reference_tokens do |ref_tok|
        res_tok = nil
        res_sym = resolve(@program_symbols, @filename, ref_tok, instr.scope)
        if res_sym.nil? #if it's null, it must be a global from another file
          res_tok = ref_tok #so just keep its name the same
        else
          res_sym.referenced # we mark it as referenced
          res_tok = res_sym.name #If we found it, go ahead and get its mangled name.
        end
        res_tok
      end
    end
    
    @instructions << instr
  end

  def new_tokenize
    @lines.each_with_index do |line, line_number|
      begin
        @parse_tree << tokenize_line(@filename, line_number, line)
      rescue ParseError => e
        parse_error_stop(e, @filename, line_number, line)
      end
    end
  end
  
  # Parse the source file into an abstract representation.
  def parse
    new_tokenize
    definitions_pass
    mangle_and_merge()
    do_main_pass()
  end

  def print_abstract
    @parse_tree.each do |abs_line|
      puts abs_line.inspect()
    end
  end
  
  # Print a listing of this module.
  def print_listing
    outlines = @instructions.map {|ins| ins.to_s}
    puts outlines.join("\n")
  end
  
  def get_abs_module
    AsmModule.new(@filename, @parse_tree, @instructions, @module_symbols, @functions)
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'yaml'
  filename = "#{ARGV.first || "out.s"}"
  om = nil
  open(filename, 'r') do |file|
    om = ObjectModule.new(filename, file.readlines)
  end
  
  unless om.nil?
    puts om.print_abstract.to_yaml
    puts om.print_listing()
    # om.print_listing
  end
end
