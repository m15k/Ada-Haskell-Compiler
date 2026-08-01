-- The pure half of ahttpd: request parsing and response rendering.
-- No sockets in here - everything is a function from strings to
-- strings, which is what makes it contract-friendly: the status
-- code is a refinement type, and the render carries a POST relating
-- the response to its body.
module Http
  ( Request (..)
  , Status
  , parseRequest
  , response
  , okText
  , okJson
  , notFound
  ) where

-- An HTTP status is not an Int; it is an Int in a range. The
-- boundary check is the compiler's, not ours.
type Status = Int in 100 .. 599

data Request = Request { reqMethod :: String, reqPath :: String }

-- "GET /path HTTP/1.1\r\n..." -> Request. Anything else is Nothing;
-- the caller answers 404 or closes.
parseRequest :: String -> Maybe Request
parseRequest raw =
  case words (takeWhile (/= '\r') (takeWhile (/= '\n') raw)) of
    (m : p : _) -> Just (Request { reqMethod = m, reqPath = p })
    _           -> Nothing

reason :: Status -> String
reason 200 = "OK"
reason 404 = "Not Found"
reason _   = "Status"

-- Deliberately no Date header: responses are a pure function of
-- the request, so the whole session is a byte-exact golden.
{-# POST response \c t b r -> length r > length b #-}
response :: Status -> String -> String -> String
response code ctype body =
  "HTTP/1.0 " ++ show code ++ " " ++ reason code ++ "\r\n"
  ++ "Server: ahttpd\r\n"
  ++ "Content-Type: " ++ ctype ++ "\r\n"
  ++ "Content-Length: " ++ show (length body) ++ "\r\n"
  ++ "Connection: close\r\n"
  ++ "\r\n"
  ++ body

okText :: String -> String
okText body = response 200 "text/plain" body

okJson :: String -> String
okJson body = response 200 "application/json" body

notFound :: String
notFound = response 404 "text/plain" "not found\n"
