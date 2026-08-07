-- Semigroup/Monoid (base-compat beyond the 2010 Report): Prelude
-- classes with defaults, instances at [a]/Text/Ordering/Maybe/(),
-- and a user instance whose mempty is a NULLARY method binding
-- (exercises pattern-form instance methods).
{-# LANGUAGE OverloadedStrings #-}
import qualified Data.Text as T

newtype Sum = Sum Int deriving (Eq, Show)

instance Semigroup Sum where
  Sum a <> Sum b = Sum (a + b)

instance Monoid Sum where
  mempty = Sum 0

main :: IO ()
main = do
  print ([1,2] <> [3 :: Int])
  print (mempty :: [Int])
  print (mconcat [[1],[2],[3 :: Int]])
  print (("ab" <> "\955c") :: T.Text)
  print (mconcat ["x", "\228", "z"] :: T.Text)
  print (mempty :: T.Text)
  print (LT <> GT, EQ <> GT, mconcat [EQ, EQ, LT, GT])
  print (Just [1] <> Nothing <> Just [2 :: Int])
  print (mappend (Sum 2) (Sum 3), mconcat [Sum 1, Sum 2, Sum 3])
  print (mempty :: Sum)
  print (("a" <> "b") :: String)
