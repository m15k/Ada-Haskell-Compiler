-- Non-strict semantics: bottoms are harmless unless demanded.
main :: IO ()
main = do
  print (fst (1, error "snd never forced"))
  print (length [error "a", error "b", error "c"])
  print (take 3 [1 ..])
  print (const 5 (error "ignored"))
  print (head (1 : error "tail never forced" : []))
  let xs = 1 : map (+ 1) xs
  print (take 5 xs)
