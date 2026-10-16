-- A where group still may not bind one name twice, even now that it
-- may shadow an argument (GHC 9.4.8: Conflicting definitions for 'y').
f :: Int -> Int
f x = x + y
  where y = 1
        y = 2
main :: IO ()
main = print (f 0)
