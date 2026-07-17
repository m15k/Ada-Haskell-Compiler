module Ops (pushAll) where

import Stack

pushAll :: [Int] -> Stack -> Stack
pushAll xs s = foldl (\acc x -> push x acc) s xs
