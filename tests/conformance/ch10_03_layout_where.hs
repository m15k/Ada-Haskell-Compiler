-- Report 10.3's parse-error(t) rule: a `where` at exactly the column
-- of the enclosing implicit block cannot begin an alternative or a
-- statement, so the block closes and the `where` attaches to the
-- declaration. Found by M141 in a JSON printer off GitHub, whose
-- case alternatives and `where` share a tab-indented column.
render :: Int -> String
render x = case x of
    0 -> tag "zero"
    1 -> tag "one"
    _ -> tag "many"
    where
      tag :: String -> String
      tag s = "<" ++ s ++ ">"

describe :: [Int] -> String
describe xs = case xs of
    [] -> none
    (y : _) -> render y
  where
    none = "<none>"

main :: IO ()
main = do
  putStrLn (render 0 ++ render 1 ++ render 7)
  putStrLn (describe [] ++ describe [1])
