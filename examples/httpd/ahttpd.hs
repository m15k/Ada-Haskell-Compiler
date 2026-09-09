-- ahttpd: an HTTP server in AHC-Haskell over Network.Socket - no
-- framework, no hidden runtime support, and since M140 no platform
-- constants either (the first version poked Darwin's sockaddr_in byte
-- by byte through the FFI). What it demonstrates, and what it honestly
-- cannot do yet, is examples/httpd/README.md.
--
--   listenOn/accept/recv/sendAll/close : Network.Socket (qualified:
--     its recv/send share names with the channel operations)
--   the accept loop PARKS on the listen fd (waitReadOr, M127) -
--     no busy-poll, an idle server costs zero CPU - and watches
--     the quit channel at the same time: Ada's accept-or-terminate
--   a handler task per connection: slow clients overlap, and the
--     schedule is still deterministic
--   /par/N answers via scope/spawn/channel fan-out whose message
--     ARRIVAL ORDER is part of the golden - the deterministic
--     scheduler makes an interleaving a testable output
--   /fact/N is exact bignum arithmetic in a response body
--   the listen port is a refinement type: ./ahttpd 70000 dies at
--     the Port boundary, not in bind()
module Main where

import Http
import Control.Concurrent.Scoped
import qualified Network.Socket as N
import qualified Data.Map as M
import qualified Data.Text as T
import System.Environment (getArgs)

-- A port IS its range.
type Port = Int in 1 .. 65535

parseNat :: String -> Maybe Int
parseNat s =
  if not (null s) && all (\c -> c >= '0' && c <= '9') s
    then Just (foldl (\acc c -> acc * 10 + (fromEnum c - 48)) 0 s)
    else Nothing

{-# PRE fact \n -> n >= 0 #-}
fact :: Int -> Integer
fact n = product [1 .. fromIntegral n]

-- The concurrency demo: k workers, each summing its own slice,
-- reporting on one channel. The FIFO scheduler makes the ARRIVAL
-- ORDER deterministic - it is asserted by the golden, not just the
-- total. GHC could compute this sum; it could never pin this order.
{-# PRE parSum \k -> k >= 1 && k <= 64 #-}
parSum :: Int -> IO String
parSum k = scope (\sc -> do
  ch <- newChan
  spawnAll sc ch 1
  parts <- collect ch k
  return (unlines (map part parts
                   ++ ["total " ++ show (sum (map snd parts))])))
  where
    slice = 1000
    spawnAll sc ch i =
      if i > k
        then return ()
        else do
          _ <- spawn sc (send ch (i, sliceSum i))
          spawnAll sc ch (i + 1)
    sliceSum i = sum [(i - 1) * slice + 1 .. i * slice]
    collect ch n =
      if n == 0
        then return []
        else do
          p <- recv ch
          rest <- collect ch (n - 1)
          return (p : rest)
    part (i, v) = "worker " ++ show i ++ ": " ++ show v

inventoryJson :: String
inventoryJson =
  "{" ++ joinComma (map pair (M.toList inv)) ++ "}\n"
  where
    inv = M.fromList
      [ ("bolts", 40 :: Int), ("nuts", 120), ("washers", 500) ]
    pair (k, v) = "\"" ++ k ++ "\": " ++ show v
    joinComma []       = ""
    joinComma [x]      = x
    joinComma (x : xs) = x ++ ", " ++ joinComma xs

index :: String
index = unlines
  [ "ahttpd - an AHC-Haskell HTTP server"
  , "routes: /  /fact/N  /par/N  /json  /quit"
  ]

-- Route to a response; Right = keep serving, Left = quit after
-- this response.
route :: String -> IO (Either String String)
route p =
  case p of
    "/"     -> return (Right (okText index))
    "/json" -> return (Right (okJson inventoryJson))
    "/quit" -> return (Left (okText "bye\n"))
    _ ->
      case splitRoute p of
        Just ("fact", n) ->
          return (Right (okText (show (fact n) ++ "\n")))
        Just ("par", n) -> do
          body <- parSum n
          return (Right (okText body))
        _ -> return (Right notFound)

-- "/fact/25" -> Just ("fact", 25)
splitRoute :: String -> Maybe (String, Int)
splitRoute ('/' : rest) =
  case break (== '/') rest of
    (name, '/' : arg) ->
      case parseNat arg of
        Just n  -> Just (name, n)
        Nothing -> Nothing
    _ -> Nothing
splitRoute _ = Nothing

-- One connection, on its own green thread: recv (parking on the
-- socket while the client dawdles), parse, log, answer, close. /quit
-- answers first, then signals the accept loop over the channel. The
-- request fits one segment for this demo.
handle :: N.Socket -> Chan () -> IO ()
handle conn quitCh = do
  raw <- N.recv conn 4096
  result <-
    case parseRequest (T.unpack raw) of
      Nothing -> do
        putStrLn "bad request -> 404"
        return (Right notFound)
      Just rq -> do
        r <- route (reqPath rq)
        putStrLn (reqMethod rq ++ " " ++ reqPath rq ++ " -> "
                  ++ status r)
        return r
  let body = either id id result
  N.sendAll conn (T.pack body)
  N.close conn
  case result of
    Left _  -> send quitCh ()
    Right _ -> return ()
  where
    status (Left _)  = "200 (quit)"
    status (Right r) = takeWhile (/= '\r') (drop 9 r)

-- The accept loop parks until the listen socket is readable OR the
-- quit channel has a message - a message wins. Each accepted
-- connection gets its own handler task; the scope joins them all
-- before the server says goodbye.
acceptLoop :: Scope -> N.Socket -> Chan () -> IO ()
acceptLoop sc lsock quitCh = do
  m <- waitReadOr (N.socketFd lsock) quitCh
  case m of
    Just _ -> return ()
    Nothing -> do
      conn <- N.accept lsock
      _ <- spawn sc (handle conn quitCh)
      acceptLoop sc lsock quitCh

main :: IO ()
main = do
  args <- getArgs
  let port = case args of
               (a : _) -> case parseNat a of
                            Just n  -> n :: Port
                            Nothing -> 8080
               _       -> 8080
  lsock <- N.listenOn port
  putStrLn "ahttpd listening"
  scope (\sc -> do
    quitCh <- newChan
    acceptLoop sc lsock quitCh)
  N.close lsock
  putStrLn "ahttpd done"
