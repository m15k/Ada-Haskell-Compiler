-- M149: error's report shows its message at the call site.
safeDiv :: Int -> Int -> Int
safeDiv _ 0 = error "division by zero requested"
safeDiv a b = a `div` b

main :: IO ()
main = do
  print (safeDiv 10 2)
  print (safeDiv 10 0)
