-- Report 3.12: let expressions - nesting, shadowing, mutual recursion,
-- polymorphic let-bound functions.
main :: IO ()
main = do
  print (let x = 5 in x + 1)
  print (let x = 1 in let x = 2 in x)
  print (let f n = if n == 0 then 0 else g (n - 1)
             g n = if n == 0 then 1 else f (n - 1)
         in (f 4, f 5))
  print (let i x = x in (i 1, i True))
  print (let (a, b) = (3, 4) in a * 10 + b)
