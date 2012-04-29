class ParamGrammar < Dhaka::Grammar

  precedences do
    left %w| + - |
    left %w| * / |
    left %w| d |
  end
  
  for_symbol(Dhaka::START_SYMBOL_NAME) do
    start                     %w| Expr |
  end
  
  for_symbol('Expr') do
    multiplication            %w| Expr * Expr |
    division                  %w| Expr / Expr |
    subtraction               %w| Expr - Expr |
    addition                  %w| Expr + Expr |
    integer                   %w| n |
    parenthetized_expression  %w| ( Expr ) |
    dice_roll_with_prefix     %w| Expr d Expr |
    dice_roll_without_prefix  %w| d Expr |
  end
  
end