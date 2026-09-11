module Text.Read (Read (..), reads, read, readMaybe, readEither) where

import Data.Char (isSpace)

--  Report 9.1 exports Read (..), reads and read from the Prelude, so
--  the class, its instances and the readsEnum_ derive support now live
--  in prelude/Prelude.hs. This module stays as the facade the Report
--  also requires: it re-exports those Prelude entities, so
--  `import Text.Read` and the implicit Prelude name the same things.

-- base's total readers (M141: an RPN calculator off GitHub wanted
-- readMaybe, which is the reason base has it - `read` on user input
-- is a crash waiting to happen).
readMaybe :: Read a => String -> Maybe a
readMaybe s =
  case [x | (x, t) <- reads s, all isSpace t] of
    [x] -> Just x
    _   -> Nothing

readEither :: Read a => String -> Either String a
readEither s =
  case readMaybe s of
    Just x  -> Right x
    Nothing -> Left "Prelude.read: no parse"
