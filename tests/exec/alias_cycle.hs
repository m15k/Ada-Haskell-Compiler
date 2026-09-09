-- Two top-level bindings that are bare aliases of each other have no
-- value: demanding either reports <<loop>> (GHC prints 2 then dies
-- the same way). Until M139 the unit's init copied NULL into both and
-- the program segfaulted with its output lost.
f :: Int -> Int
f x = x + 1

p :: Int
p = q

q :: Int
q = p

main :: IO ()
main = do
  print (f 1)
  print p
