#Resolve a symbol in the current tables.
def resolve(symbol_table, filename, symbol_name, current_global = nil)
  if symbol_name.start_with?('.') #local label
    if current_global.nil?
      puts "Cannot locate local symbol without global context. #{filename}, #{symbol_name}"
      exit 1
    end
    resolve_name = AsmSymbol::make_local_name(current_global, symbol_name)
    return symbol_table[resolve_name]
  else #global label
    #check for a module-private definition
    private_name = AsmSymbol::make_private_name(filename, symbol_name)
    symbol = symbol_table[private_name]
    return symbol unless symbol.nil?
    
    #check for a global definition
    symbol = symbol_table[symbol_name]
    return symbol
  end
end

