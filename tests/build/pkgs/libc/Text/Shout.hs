-- A bare module tree: no ahc.toml at all, just modules by path.
module Text.Shout (shout) where

import Data.Char (toUpper)

shout :: String -> String
shout = map toUpper
