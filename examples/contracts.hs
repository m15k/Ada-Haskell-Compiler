-- Function contracts: Ada's Pre/Post, as AHC pragmas.
--
--   scripts/ahc-build.sh examples/contracts.hs
--   ./examples/contracts
--
-- A contract is an ordinary Haskell predicate attached to a
-- function by name:
--
--   {-# PRE  f  \arg1 .. argN -> Bool          #-}
--   {-# POST f  \arg1 .. argN result -> Bool   #-}
--
-- The predicate is typechecked against f's own signature (its type
-- variables and class context included), and checked at run time
-- when f's result is demanded: the precondition first, then the
-- body, then the postcondition against the shared result. Because
-- Haskell is pure there is no Ada 'Old - a postcondition simply
-- names the arguments, which cannot have changed.
--
-- Contracts are claims, not semantics: compile with
-- AHC_UNCHECKED=1 (ahc emit --unchecked) and they vanish, exactly
-- like refinement-type checks - Ada's assertion policy.
--
-- GHC note: GHC ignores these pragmas (a warning on stderr), so a
-- contract-carrying program is still ordinary portable Haskell -
-- it simply runs unchecked there.

-- 1. The classic: a relation BETWEEN arguments (lo <= hi), and a
--    result bounded BY arguments - neither is expressible as a
--    refinement type on any single value.
{-# PRE  clamp \lo hi x -> lo <= hi #-}
{-# POST clamp \lo hi x r -> lo <= r && r <= hi #-}
clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

-- 2. A full functional specification: the postcondition here is
--    strong enough to CHARACTERIZE integer square root, so any
--    implementation bug that survives it is a bug in the spec too.
{-# PRE  isqrt \n -> n >= 0 #-}
{-# POST isqrt \n r -> r * r <= n && n < (r + 1) * (r + 1) #-}
isqrt :: Integer -> Integer
isqrt n = go 0
  where
    go k = if (k + 1) * (k + 1) > n then k else go (k + 1)

-- 3. Contracts may call ordinary functions - including your own
--    helpers - because they ARE ordinary typechecked Haskell.
sorted :: [Int] -> Bool
sorted (x : y : rest) = x <= y && sorted (y : rest)
sorted _ = True

{-# PRE  binSearch \xs k -> sorted xs #-}
binSearch :: [Int] -> Int -> Bool
binSearch xs k = go xs
  where
    go [] = False
    go ys =
      case splitAt (length ys `div` 2) ys of
        (lo, m : hi) ->
          if k == m then True
          else if k < m then go lo else go hi
        (lo, []) -> go lo

-- 4. Polymorphic functions carry polymorphic contracts: this one
--    inherits `Ord a` from the signature, and the checks work at
--    every instantiation.
{-# POST maxOf \x y r -> r >= x && r >= y #-}
maxOf :: Ord a => a -> a -> a
maxOf x y = if x >= y then x else y

-- 5. Laziness: contracts fire when a result is DEMANDED. The
--    misApplied binding below violates clamp's precondition, but
--    the program never demands it, so nothing fires - exactly like
--    an unused refined value. Force it (uncomment the print) to
--    see: ahc: precondition of 'clamp' violated
main :: IO ()
main = do
  print (clamp 0 100 250, clamp 0 100 (-7))
  print (map isqrt [0, 8, 9, 10, 10 ^ 12])
  print (binSearch [1, 3, 5, 8, 13] 8, binSearch [1, 3, 5] 4)
  print (maxOf (2 :: Int) 9, maxOf "abc" "abd")
  let misApplied = clamp 100 0 5     -- pre is False; undemanded
  print (clamp 1 10 (fromIntegral (isqrt 90)))  -- contracts compose
  -- print misApplied                -- uncomment: dies with the
  --                                 -- precondition message
