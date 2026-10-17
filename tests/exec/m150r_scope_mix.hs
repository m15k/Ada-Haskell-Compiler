import Control.Concurrent.Scoped
import Control.Concurrent.Protected
import Control.Parallel

work :: Int -> Integer
work k = product [1 .. fromIntegral (k `mod` 40 + 20)]

pw :: Int -> Int
pw k = let a = length (show (work k)); b = length (show (work (k+3)))
       in a `par` (b `pseq` (a + b))

round' :: Int -> IO Int
round' k = do
  p <- newProtected (0 :: Integer)
  ch <- newChan
  x <- scope (\s -> do
    t1 <- spawn s (entry p (> 0) (\v -> (v + work k, pw k)))
    t2 <- spawn s (updating p (\v -> (v + work (k + 1), ())))
    t3 <- spawn s (do { v <- recv ch; return (v + pw (k+1)) })
    send ch (pw (k + 2))
    a <- await t1
    _ <- await t2
    c <- await t3
    let go 0 = 0
        go n = n + og (n - 1)
        og 0 = 0
        og n = a + go (n - 1)
    return (go (c `mod` 7 + 3)))
  r <- reading p (length . show)
  return (r + x)

main :: IO ()
main = do
  rs <- mapM round' [1 .. 300]
  print (sum rs)
