require 'rubygems'
require File.expand_path(File.dirname(__FILE__) + '/resolve.rb')

require File.expand_path(File.dirname(__FILE__) + '/line_tok.rb') 

$DONT_STOP_ON_ERROR = false

unless $config
  $config = {}
  $config[:hacking] = true
end

def parse_error_stop(e, source_file, line_number, line)
  puts "FATAL LINK ERROR"
  puts "Error: #{e.msg}"
  puts "in file #{source_file} on line #{line_number + 1}"
  puts "Errant Line: #{line}"
  puts e.backtrace if $config[:hacking]
  exit 1 unless $DONT_STOP_ON_ERROR
end


#Represents a single .S module file.
class ObjectModule
  attr_reader :filename, :lines
  attr_accessor :instructions, :module_symbols, :program_symbols


  # Create a module from source lines.
  def initialize(file_name, source_lines)
    @filename = file_name
    @lines = source_lines
    @instructions = []
    @module_symbols = {}
    @program_symbols = {}
    @module_private_symbols = []
    @parse_tree = []
  end

  # Clean and normalize the source
  def normalize
    @lines.map! {|line| line.gsub(/;.*$/, '').gsub(/\s+/, ' ').strip}
  end

  # Is this line empty?
  def empty_line(line)
    return (line.nil? || line.empty? || line =~ /^\s+$/) #skip empty lines or whitespace lines
  end

  # Extract all symbols *defined* by this module.
  # References are not handled at this stage.
  def definitions_pass
    last_global_symbol = nil
    @lines.each_with_index do |line, line_number|
      next if empty_line(line)
      if line =~ LABEL_DEF_RE
        if empty_line($1)
          next
        end
        label = $1.strip
        parent = nil
        if label.start_with?('.')
          parent = last_global_symbol
        end
        defined_symbol = AsmSymbol.new(@filename, label, parent)
        @module_symbols[defined_symbol.name] = defined_symbol
        if parent.nil? #it's a global
          last_global_symbol = defined_symbol
        else #it's a local, attach dependency.
          last_global_symbol.attach_local(defined_symbol) 
        end

      elsif line =~ HIDDEN_SYM_RE
        hidden_symbol = $2
        @module_private_symbols << hidden_symbol
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
  def parse_label_pending(label_def, last_global_symbol, pending_symbols)
    retval = []
    new_local = false
    if label_def.start_with?('.')
      new_local = true
      resolved_symbol = resolve(@program_symbols, @filename, label_def, last_global_symbol)
    else
      new_local = false
      resolved_symbol = resolve(@program_symbols, @filename, label_def, nil)
    end
    if resolved_symbol.nil?
      puts "Resolved null symbol (#{label_def}) during parse phase. Should not happen."
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


    @lines.each_with_index do |line, line_number|
      if empty_line(line)
        next
      end

      if line =~ HIDDEN_SYM_RE 
        #already used by the definitions phase
        next
      end

      if line =~ /^\s*(#{SECTION_RE})\s*$/
        case $1
        when '.text'
          current_section = :text
        when '.data'
          current_section = :data
        end

        next
      end

      if line =~ /^\s*(#{DIRECTIVE_RE})/
        #only visibility at the moment, skip
        next
      end

      if line =~ /^\s*(#{NULL_DIR_RE})/
        #null ops that we ignore
        next
      end

      if line =~ /^\s*#{LABEL_DEF_RE}\s*$/
        #this is a standalone symbol definition, save it to define it later.
        label_def = $1.strip
        last_global_symbol = parse_label_pending(label_def, last_global_symbol, pending_symbols)
        next
      end

#      debugger
      unless line =~ STRING_LINE || line =~ TWO_PARAM_LINE || line =~ ONE_PARAM_LINE
        parse_error_stop("Cannot parse line.", @filename, line_number, line)
      end

      label = $1
      instruction = $2.downcase
      param_a = $3
      param_b = $4
      
      param_a.strip if param_a
      param_b.strip if param_b

      unless empty_line(label)
        label_def = label.strip
        last_global_symbol = parse_label_pending(label_def, last_global_symbol, pending_symbols)
      end

      instr = nil

      if instruction =~ DATA_WORD_RE || instruction.strip =~ /\.string|\.asciz/i
        begin
          instr = InlineData.new(@filename, last_global_symbol, pending_symbols, param_a, line_number)
        rescue ParseError => e
          parse_error_stop(e.msg, @filename, line_number, line)
        end
      else #try to parse as regular instruction
        
        begin
          instr = Instruction.new(@filename, last_global_symbol, pending_symbols, instruction, param_a, param_b, line_number)
        rescue ParseError => e
          parse_error_stop(e.msg, @filename, line_number, line)
        end
      end

      pending_symbols.each do |sym|
        sym.define(instr)
      end
      pending_symbols = []
      @instructions << instr
    end
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
    normalize()
    new_tokenize
    puts @parse_tree.map {|abstract| abstract.inspect}
    #definitions_pass()
    #mangle_and_merge()
    #do_main_pass()
  end

  # Print a listing of this module.
  def print_listing
    outlines = @instructions.map {|ins| ins.to_s}
    puts outlines.join("\n")
  end
end

if __FILE__ == $PROGRAM_NAME
  filename = "#{ARGV.first || "out.s"}"
  om = nil
  open(filename, 'r') do |file|
    om = ObjectModule.new(filename, file.readlines)
  end
  
  unless om.nil?
    om.parse
    # om.print_listing
  end
end
