module Network.Socket
  ( Socket, socketFd
  , listenOn, accept, connectTo
  , recv, send, sendAll, close
  ) where

import Control.Concurrent.Scoped (waitRead, waitWrite)

-- TCP over IPv4, the subset a text-protocol server or client needs
-- (M140; docs/plans/2026-09-08-m140-sockets.md). The constants and the
-- sockaddr layout live in the runtime, so a program over this module
-- carries nothing platform-specific. Every socket is nonblocking; a
-- call that would block PARKS this green thread on the fd (M127) and
-- every other task keeps running. Failures are IOErrors with the
-- errno-derived type, catchable like any other. Payloads are Text -
-- the packed byte type - so invalid UTF-8 on the wire normalises to
-- U+FFFD: this is a text-protocol socket, not a byte pipe.
-- AHC_SOCKET_DEBUG=1 traces every call to stderr.

-- Socket is ABSTRACT: the constructor stays private, so the only
-- sockets in circulation come from listenOn/accept/connectTo.
data Socket = MkSocket Int deriving (Eq)

-- The fd, for waitReadOr (watching a socket and a channel at once).
socketFd :: Socket -> Int
socketFd (MkSocket fd) = fd

-- Listen on a port (INADDR_ANY, SO_REUSEADDR) with the given backlog.
listenOn :: Int -> IO Socket
listenOn port = primSockListen port 16 >>= \fd -> return (MkSocket fd)

-- Park until a connection arrives, then hand it out (nonblocking).
accept :: Socket -> IO Socket
accept s@(MkSocket lfd) =
  primSockAccept lfd >>= \fd ->
  if fd < 0 then waitRead lfd >> accept s else return (MkSocket fd)

-- Connect to a numeric IPv4 address ("127.0.0.1") and port.
connectTo :: String -> Int -> IO Socket
connectTo host port =
  primSockConnect (primTextPack host) port >>= \fd -> return (MkSocket fd)

-- Up to n bytes; "" at end of file; parks while nothing is readable.
recv :: Socket -> Int -> IO Text
recv s@(MkSocket fd) n =
  primSockRecv fd n >>= \r -> case r of
    Nothing -> waitRead fd >> recv s n
    Just t -> return t

-- Write once: the number of bytes accepted (possibly fewer than
-- offered); parks while the socket is not writable.
send :: Socket -> Text -> IO Int
send s@(MkSocket fd) t =
  primSockSend fd t >>= \k -> if k < 0 then waitWrite fd >> send s t else return k

-- Write everything, however many rounds it takes. A partial write
-- is resumed by dropping the bytes accepted; Text drops by code
-- point, so the resume point is exact for ASCII wire text and lands
-- on the next code-point boundary otherwise (a text-protocol socket).
sendAll :: Socket -> Text -> IO ()
sendAll s t =
  if primTextByteLength t == 0 then return ()
  else send s t >>= \k -> sendAll s (dropBytes k t)
  where
    dropBytes k u =
      let u' = primTextDrop 1 u
      in if k <= 0 || primTextByteLength u == 0 then u
         else dropBytes (k - (primTextByteLength u - primTextByteLength u')) u'

close :: Socket -> IO ()
close (MkSocket fd) = primSockClose fd
