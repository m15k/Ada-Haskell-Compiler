-- seq is STRICT in its first argument and only there; ($!) forces
-- before applying; foldl' keeps the accumulator evaluated. The die
-- message after "before" pins that seq really forces (a lazy seq
-- would print "unreached").
main :: IO ()
main = do
  putStrLn "before"
  putStrLn (const "const ignores its second argument" undefined)
  print (seq (error "seq forced its first argument") (5 :: Int))
  putStrLn "unreached"
