-- Report 4.4.3/4.5: where clauses scoping over guards; function
-- bindings with multiple equations and guards.
grade :: Int -> Int
grade n
  | n >= high = 1
  | n >= mid  = 2
  | otherwise = 3
  where
    high = 90
    mid  = 50

fib :: Int -> Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)

main :: IO ()
main = do
  print (grade 95, grade 70, grade 10)
  print (map fib [0 .. 8])
