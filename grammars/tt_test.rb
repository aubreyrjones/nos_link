require 'yaml'

require 'polyglot'
require 'treetop'

require 'D16Asm'

$parser = D16AsmParser.new

def parse(str)
	$parser.parse str
end

def yp(str)
	puts YAML.dump(parse(str).content)
end


yp '[4+sp+32], 0x23 -65, a'

