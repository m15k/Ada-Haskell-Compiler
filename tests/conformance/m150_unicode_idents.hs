-- M150: Unicode identifiers and operators (Haskell 2010 Report 2.2,
-- 2.4), with GHC's character classes.
module Main where

-- Spanish, Greek, Cyrillic, CJK variables; a Greek constructor.
data Forma = Círculo Double | Δ Double Double
  deriving Show

área :: Forma -> Double
área (Círculo r) = 3 * r * r
área (Δ b h) = b * h / 2

λx :: Int -> Int
λx n = n * 2

привет :: String
привет = "мир"

数 :: Int
数 = 42

-- Letters may continue with marks, modifier letters and primes.
año' :: Int
año' = 2026

x̃, aʰ :: Int
x̃ = 7
aʰ = 8

-- Unicode operators: math symbols and other punctuation.
infixr 9 ∘
(∘) :: (b -> c) -> (a -> b) -> a -> c
f ∘ g = \x -> f (g x)

(⊕) :: Int -> Int -> Int
a ⊕ b = a * 10 + b

(·) :: Int -> Int -> Int
a · b = a * b

data Par = Int :⊗ Int deriving Show

main :: IO ()
main = do
  let ñ = 1 :: Int
      café = ñ + 1
  print (ñ, café)
  print (área (Círculo 1), área (Δ 4 3))
  print (Δ 1 2)
  print (λx 21, привет, 数, año')
  print ((λx ∘ λx) 3, 1 ⊕ 2, 3 :⊗ 4, 6 · 7, x̃ + aʰ)
  print [ x | x <- [ñ .. café] ]
