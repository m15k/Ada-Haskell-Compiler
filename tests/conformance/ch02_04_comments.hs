-- Report 2.4: line comments, block comments, nesting.
{- a block comment -}
main :: IO ()  -- trailing line comment
{- nested {- inner {- deepest -} -} still a comment -}
main = do
  print 1 {- inline -}
  print {- between -} 2
  print 3
