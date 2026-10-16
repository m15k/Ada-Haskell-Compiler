{-# LANGUAGE LambdaCase #-}
-- M150: strict let / where / do bindings, and \cases with bangs.
import Control.Exception

probe :: Show a => String -> a -> IO ()
probe name v = do
  r <- try (evaluate v)
  putStrLn (name ++ ": " ++ case r of
    Left e -> const "forced" (e :: ErrorCall)
    Right x -> show x)

probeIO :: String -> IO () -> IO ()
probeIO name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ ": " ++ const "forced" (e :: ErrorCall))
    Right () -> return ()

letStrict :: Int
letStrict = let !x = (undefined :: Int) in 1

letLazy :: Int
letLazy = let x = (undefined :: Int) in 1

-- Only the pair is forced, not its components.
letPair :: Int
letPair = let !(a, b) = (undefined, 2 :: Int) in b

letWild :: Int
letWild = let !_ = (undefined :: Int) in 3

-- The where binding is forced before the guards are tried.
whereStrict :: Int -> String
whereStrict n
  | n > 0 = "positive"
  | otherwise = "other"
  where !check = if n == 99 then undefined else n

-- A strict binding's variable is usable in the body.
letUse :: Int
letUse = let !y = 20 + 1 in y * 2

twoArgs :: Int -> Int -> Int
twoArgs = \cases
  !a 0 -> 0
  _ b -> b

main :: IO ()
main = do
  probe "let !x" letStrict
  probe "let x" letLazy
  probe "let !(a, b)" letPair
  probe "let !_" letWild
  probe "where 1" (length (whereStrict 1))
  probe "where 99" (length (whereStrict 99))
  probe "let use" letUse
  probe "\\cases !a 0" (twoArgs undefined 0)
  probe "\\cases _ b" (twoArgs undefined 5)
  probeIO "do !x <-" $ do
    !x <- return (undefined :: Int)
    putStrLn "not reached"
  probeIO "do x <-" $ do
    x <- return (undefined :: Int)
    putStrLn "do x <-: lazy"
  probeIO "do let !x" $ do
    let !x = (undefined :: Int)
    putStrLn "not reached"
