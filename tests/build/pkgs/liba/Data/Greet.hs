-- A dependency module that itself leans on a transitive
-- dependency (Text.Shout, from the manifest-less libc tree)
-- and, through it, the stdlib.
module Data.Greet (greeting) where

import Text.Shout (shout)

greeting :: String -> String
greeting who = shout ("hello, " ++ who)
