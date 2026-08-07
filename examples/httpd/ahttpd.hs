-- ahttpd: an HTTP server in AHC-Haskell, straight over the libc
-- socket API through the FFI - no framework, no hidden runtime
-- support. What it demonstrates, and what it honestly cannot do
-- yet, is examples/httpd/README.md.
--
--   socket/bind/listen/accept/read/write/close : foreign imports
--   sockaddr_in built byte-by-byte with the marshal surface
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
{-# LANGUAGE ForeignFunctionInterface #-}
module Main where

import Http
import Control.Concurrent.Scoped
import qualified Data.Map as M
import System.Environment (getArgs)

foreign import ccall "socket"     c_socket :: CInt -> CInt -> CInt -> IO CInt
foreign import ccall "setsockopt" c_setsockopt
  :: CInt -> CInt -> CInt -> Ptr a -> CInt -> IO CInt
foreign import ccall "bind"   c_bind   :: CInt -> Ptr a -> CInt -> IO CInt
foreign import ccall "listen" c_listen :: CInt -> CInt -> IO CInt
foreign import ccall "accept" c_accept :: CInt -> Ptr a -> Ptr b -> IO CInt
foreign import ccall "fcntl"  c_fcntl  :: CInt -> CInt -> CInt -> IO CInt
foreign import ccall "read"   c_read   :: CInt -> Ptr a -> CInt -> IO CInt
foreign import ccall "write"  c_write  :: CInt -> String -> CInt -> IO CInt
foreign import ccall "close"  c_close  :: CInt -> IO CInt

-- Darwin constants (Linux: SOL_SOCKET 1, SO_REUSEADDR 2,
-- O_NONBLOCK 0x800, and sockaddr_in starts with a 16-bit family
-- instead of len+family bytes).
afInet, sockStream, solSocket, soReuseAddr, fSetFl, oNonblock :: CInt
afInet      = 2
sockStream  = 1
solSocket   = 65535
soReuseAddr = 4
fSetFl      = 4
oNonblock   = 4

-- A port IS its range.
type Port = Int in 1 .. 65535

-- sockaddr_in, poked a byte at a time: len, family, port in
-- network order, INADDR_ANY from the zeroing.
mkSockAddr :: Port -> IO (Ptr ())
mkSockAddr port = do
  sa <- mallocBytes 16
  pokeInt64 sa 0 0
  pokeInt64 sa 8 0
  pokeWord8 sa 0 16
  pokeWord8 sa 1 (fromIntegral afInet)
  pokeWord8 sa 2 (fromIntegral (port `div` 256))
  pokeWord8 sa 3 (fromIntegral (port `mod` 256))
  return sa

-- Nonblocking read: EAGAIN parks THIS handler on the fd (M127);
-- every other task keeps running until the bytes arrive. The
-- request fits one segment for this demo.
readRequest :: CInt -> Ptr Char -> IO Int
readRequest fd buf = do
  n <- c_read fd buf 4096
  if n < 0
    then waitRead (fromIntegral fd) >> readRequest fd buf
    else return (fromIntegral n)

-- The connection is O_NONBLOCK, so a write can refuse outright
-- (EAGAIN) or accept only part of the body. Ignoring the result is
-- how a CI runner got an EMPTY response while the server's own log
-- said the request had been served: park on the fd until it is
-- writable and finish the job. This is waitWrite's reason to exist.
writeAll :: CInt -> String -> IO ()
writeAll fd s =
  if null s
    then return ()
    else do
      k <- c_write fd s (fromIntegral (length s))
      if k <= 0
        then waitWrite (fromIntegral fd) >> writeAll fd s
        else writeAll fd (drop (fromIntegral k) s)

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

-- One connection, on its own green thread: read (parking on the
-- fd while the client dawdles), parse, log, answer, close. /quit
-- answers first, then signals the accept loop over the channel.
handle :: CInt -> Chan () -> IO ()
handle fd quitCh = do
  _ <- c_fcntl fd fSetFl oNonblock
  buf <- mallocBytes 4096
  n <- readRequest fd buf
  raw <- peekCStringLen buf n
  free buf
  result <-
    case parseRequest raw of
      Nothing -> do
        putStrLn "bad request -> 404"
        return (Right notFound)
      Just rq -> do
        r <- route (reqPath rq)
        putStrLn (reqMethod rq ++ " " ++ reqPath rq ++ " -> "
                  ++ status r)
        return r
  let body = either id id result
  writeAll fd body
  _ <- c_close fd
  case result of
    Left _  -> send quitCh ()
    Right _ -> return ()
  where
    status (Left _)  = "200 (quit)"
    status (Right r) = takeWhile (/= '\r') (drop 9 r)

-- The accept loop parks until the listen fd is readable OR the
-- quit channel has a message - a message wins. Each accepted
-- connection gets its own handler task; the scope joins them all
-- before the server says goodbye.
acceptLoop :: Scope -> CInt -> Chan () -> IO ()
acceptLoop sc lfd quitCh = do
  m <- waitReadOr (fromIntegral lfd) quitCh
  case m of
    Just _ -> return ()
    Nothing -> do
      fd <- c_accept lfd nullPtr nullPtr
      if fd < 0
        then acceptLoop sc lfd quitCh
        else do
          _ <- spawn sc (handle fd quitCh)
          acceptLoop sc lfd quitCh

main :: IO ()
main = do
  args <- getArgs
  let port = case args of
               (a : _) -> case parseNat a of
                            Just n  -> n :: Port
                            Nothing -> 8080
               _       -> 8080
  lfd <- c_socket afInet sockStream 0
  one <- mallocBytes 4
  pokeInt32 one 0 1
  _ <- c_setsockopt lfd solSocket soReuseAddr one 4
  free one
  sa <- mkSockAddr port
  brc <- c_bind lfd sa 16
  free sa
  if brc /= 0
    then putStrLn "bind failed"
    else do
      _ <- c_listen lfd 16
      _ <- c_fcntl lfd fSetFl oNonblock
      putStrLn "ahttpd listening"
      scope (\sc -> do
        quitCh <- newChan
        acceptLoop sc lfd quitCh)
      _ <- c_close lfd
      putStrLn "ahttpd done"
