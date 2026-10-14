-- Scopes and protected-value waiters retired by the hundred: each
-- round opens a scope, parks one child on an entry barrier, lets
-- the other enable it, then closes the scope (M150 collector fix).
import Control.Concurrent.Scoped
import Control.Concurrent.Protected

work :: Int -> Integer
work k = product [1 .. fromIntegral (k `mod` 40 + 20)]

round' :: Int -> IO Int
round' k = do
  p <- newProtected (0 :: Integer)
  scope (\s -> do
    t1 <- spawn s (entry p (> 0) (\v -> (v + work k, ())))
    t2 <- spawn s (updating p (\v -> (v + work (k + 1), ())))
    await t1
    await t2)
  reading p (length . show)

main :: IO ()
main = do
  rs <- mapM round' [1 .. 400]
  print (sum rs)
