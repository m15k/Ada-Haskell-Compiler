-- M150: layout columns count code points, not bytes, so blocks that
-- open after a multi-byte identifier on the same line align as in GHC.

café :: Int
café = let α = 1
           β = 2
       in α + β

größe :: Int -> Int
größe n = case n of 0 -> 10
                    _ -> 20

über :: IO ()
über = do putStrLn "ü1"
          putStrLn "ü2"

данные :: [Int]
данные = [ x | x <- [1 .. 3] ] where ä = 0
                                     ö = ä

main :: IO ()
main = do
  print café
  print (größe 0, größe 1)
  über
  print данные
