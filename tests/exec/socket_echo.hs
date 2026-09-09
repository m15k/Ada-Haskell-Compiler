-- Network.Socket on the loopback, server and client as green tasks in
-- ONE program (Network.Socket imported qualified: its recv/send share
-- their names with the channel operations, as GHC's network does):
-- the schedule is the deterministic scheduler's, so the
-- transcript is a golden. The server parks in N.accept and N.recv (no
-- busy-poll); the client parks in N.recv while the server thinks.
import Control.Concurrent.Scoped
import qualified Network.Socket as N
import qualified Data.Text as T

server :: N.Socket -> Int -> IO ()
server lsock n =
  if n == 0 then return () else do
    conn <- N.accept lsock
    msg <- N.recv conn 1024
    putStrLn ("server got: " ++ T.unpack msg)
    N.sendAll conn (T.pack ("echo " ++ T.unpack msg ++ "\n"))
    N.close conn
    server lsock (n - 1)

client :: Int -> String -> IO ()
client port s = do
  c <- N.connectTo "127.0.0.1" port
  N.sendAll c (T.pack s)
  reply <- N.recv c 1024
  putStr ("client got: " ++ T.unpack reply)
  N.close c

main :: IO ()
main = do
  let port = 18841
  lsock <- N.listenOn port
  scope (\sc -> do
    spawn sc (server lsock 3)
    spawn sc (client port "one")
    spawn sc (client port "two")
    spawn sc (client port "three")
    return ())
  N.close lsock
  -- a refused connection is an IOError, caught like any other
  primCatch (N.connectTo "127.0.0.1" 1 >> putStrLn "unreached")
            (\e -> putStrLn ("refused: " ++ primIoeLocation (primExcIO e)))
  putStrLn "done"
