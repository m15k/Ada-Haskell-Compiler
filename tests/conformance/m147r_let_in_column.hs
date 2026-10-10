-- Report 10.3 parse-error(t): `in` at the column of a let block's
-- bindings closes the block (M147 scout, cnyegun/json-haskell).
f :: Maybe Int -> Int
f m = case m of
  Just x ->
    let y = x * 2
        z = y + 1
        in y + z
  Nothing -> 0

main :: IO ()
main = do
  let a = 3
      in print (f (Just a))
  r <- do
    let b = 4
    let Just c = Just b
        in return (c + 1)
  print (r, f Nothing)
