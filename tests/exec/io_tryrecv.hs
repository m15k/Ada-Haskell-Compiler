-- M127: tryRecv never parks - Nothing on empty, Just in FIFO order.
import Control.Concurrent.Scoped

main :: IO ()
main = do
  c <- newChan
  r0 <- tryRecv c
  print (r0 :: Maybe Int)
  send c 7
  send c 8
  r1 <- tryRecv c
  r2 <- tryRecv c
  r3 <- tryRecv c
  print r1
  print r2
  print r3
