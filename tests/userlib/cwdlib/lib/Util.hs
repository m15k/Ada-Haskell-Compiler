module Util where
-- A user project's own ./lib is a USER module: it sees only what GHC's
-- Prelude exports, not base's internal helpers.
g :: Int -> Int
g x = foldrList_ (+) 0 [x]
