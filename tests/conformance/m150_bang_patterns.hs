{-# LANGUAGE LambdaCase #-}
-- M150: bang patterns in every pattern position, and `!` still an
-- operator when it is not a prefix occurrence (GHC 9's rule).
import Control.Exception

-- Does evaluating v to WHNF raise? Prints "forced" or the value.
probe :: Show a => String -> a -> IO ()
probe name v = do
  r <- try (evaluate v)
  putStrLn (name ++ ": " ++ case r of
    Left e -> const "forced" (e :: ErrorCall)
    Right x -> show x)

sumTo :: Int -> Int -> Int
sumTo !acc 0 = acc
sumTo !acc n = sumTo (acc + n) (n - 1)

constOne :: Int -> Int
constOne !_ = 1

lazyOne :: Int -> Int
lazyOne _ = 1

firstOf :: (Int, Int) -> Int
firstOf (!a, _) = 7

justBang :: Maybe Int -> Int
justBang (Just !x) = 2
justBang Nothing = 0

underLazy :: Int -> Int
underLazy ~(!x) = 3

guarded :: Int -> String
guarded !n
  | n > 0 = "positive"
  | otherwise = "not positive"

-- `!` as an operator: loose infix defines it, tight infix uses it.
infixl 9 !
(!) :: [a] -> Int -> a
xs ! i = xs !! i

-- A bang under a newtype constructor forces the wrapped value.
newtype Box = Box Int
boxed :: Box -> Int
boxed (Box !_) = 8

main :: IO ()
main = do
  print (sumTo 0 100)
  probe "equation !_" (constOne undefined)
  probe "equation _" (lazyOne undefined)
  probe "tuple (!a, _)" (firstOf (undefined, 2))
  probe "Just !x" (justBang (Just undefined))
  probe "~(!x)" (underLazy undefined)
  probe "lambda" ((\ !x -> 4 :: Int) undefined)
  probe "lambda lazy" ((\x -> 4 :: Int) undefined)
  probe "case !_" (case (undefined :: Int) of !_ -> 5 :: Int)
  probe "case _" (case (undefined :: Int) of _ -> 5 :: Int)
  probe "\\case" ((\case !_ -> 6 :: Int) (undefined :: Int))
  probe "newtype Box !_" (boxed (Box undefined))
  putStrLn (guarded 3)
  print ([10, 20, 30] ! 1, [10, 20, 30]!2, map (! 0) [[1], [2 :: Int]])
  print ((!) "abc" 0)
