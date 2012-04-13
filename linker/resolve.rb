#Resolve a symbol in the current tables.
#
# The resolution process is:
# (1) if symbol_name starts with '.', try to find a local symbol in the given global scope
# (1a) If no local symbol found, that is an error.
#
# (2) The name is mangled according to the rules for .private/.hidden, and an attempt is
#     made to locate that name.
#
# (3) An attempt is made to locate the raw, unmangled name.
#
# A return value of nil indicates an undefined symbol.
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

