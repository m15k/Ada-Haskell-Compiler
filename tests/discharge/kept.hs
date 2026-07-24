-- Argument-dependent contracts: the evaluator must NOT discharge
-- these (opaque parameters poison the comparison); the harness
-- expects check_claim in the generated C, and the violation still
-- fires at runtime.
{-# PRE clamp \lo hi x -> lo <= hi #-}
clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

main :: IO ()
main = print (clamp 0 10 99)
