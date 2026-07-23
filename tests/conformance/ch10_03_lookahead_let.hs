-- Report 10.3: a single-line let-in inside an explicit-brace case
-- alternative, inside a do block. The do-statement bind/expression
-- lookahead must not drag the layout engine past the 'let' - its
-- implicit context can only be closed by the parse-error(t) rule,
-- which needs the parser co-routined. Fuzzer find (M76, seed 3).
main :: IO ()
main = do
  print (case [1 :: Int] of { [] -> 0 ; (x : _) -> (let v = 2 in v + x) })
  print (case "ab" of { [] -> 'z' ; (c : _) -> (let u = c in u) })
