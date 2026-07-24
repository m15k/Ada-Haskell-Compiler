-- A provably-false precondition warns at compile time (pinned by
-- scripts/run_discharge.sh) and still fails at demand time with
-- the standard message.
{-# PRE broken \x -> 2 + 2 == 5 #-}
broken :: Int -> Int
broken x = x

main :: IO ()
main = do
  putStrLn "before"
  print (broken 1)
