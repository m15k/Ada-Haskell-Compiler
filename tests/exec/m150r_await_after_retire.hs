import Control.Concurrent.Scoped
import Control.Monad

main :: IO ()
main = do
  r <- scope $ \s1 -> do
    ch <- newChan
    x <- spawn s1 $ do
           t <- recv ch
           replicateM_ 3 yield
           v <- await t
           return (v :: Int)
    scope $ \s2 -> do
      t <- spawn s2 (replicateM_ 10 yield >> return 42)
      send ch t
    putStrLn "inner scope closed"
    await x
  print r
