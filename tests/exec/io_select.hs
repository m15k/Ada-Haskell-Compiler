-- M127: selectRecv takes the first non-empty channel in LIST ORDER
-- (the pinned tie-break), and parks on all of them when empty -
-- woken by whichever send arrives, index attached.
import Control.Concurrent.Scoped

main :: IO ()
main = do
  a <- newChan
  b <- newChan
  send a "from-a"
  send b "from-b"
  (i, v) <- selectRecv [a, b]
  putStrLn (show i ++ " " ++ v)
  (j, w) <- selectRecv [a, b]
  putStrLn (show j ++ " " ++ w)
  scope (\sc -> do
    _ <- spawn sc (send b "late")
    (k, x) <- selectRecv [a, b]
    putStrLn (show k ++ " " ++ x))
