import Control.Concurrent.Scoped
import Control.Monad

work :: Int -> Integer
work k = product [1 .. fromIntegral (k `mod` 40 + 20)]

round' :: Int -> IO Int
round' k = scope (\s -> do
    ts <- mapM (\j -> spawn s (return $! length (show (work (k + j))))) [1 .. 9]
    rs <- mapM await ts
    return (sum rs))

main :: IO ()
main = do
  rs <- mapM round' [1 .. 300]
  print (sum rs)
