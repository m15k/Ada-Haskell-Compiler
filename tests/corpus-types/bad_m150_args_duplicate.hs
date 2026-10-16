-- One equation's patterns still may not bind one name twice (GHC
-- 9.4.8: Conflicting definitions for 'x').
f :: Int -> Int -> Int
f x x = x
main :: IO ()
main = print (f 1 2)
