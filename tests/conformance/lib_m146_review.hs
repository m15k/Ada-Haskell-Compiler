-- Regressions from M146's adversarial review, oracled against GHC 9.4.8.
import Data.Ratio
import Data.Word

-- An Enum instance with only toEnum/fromEnum: the Report's class
-- defaults supply succ, pred and the four enumerations.
newtype N = N Int deriving (Eq, Ord, Show)
instance Enum N where
  toEnum = N
  fromEnum (N a) = a

-- A Fractional instance without recip (default 1 / x) and one
-- without (/) (default x * recip y).
newtype F = F Double deriving (Show)
instance Num F where
  F a + F b = F (a + b)
  F a * F b = F (a * b)
  abs (F a) = F (abs a)
  signum (F a) = F (signum a)
  fromInteger = F . fromInteger
  negate (F a) = F (negate a)
instance Fractional F where
  F a / F b = F (a / b)
  fromRational = F . fromRational
newtype G = G Double deriving (Show)
instance Num G where
  G a + G b = G (a + b)
  G a * G b = G (a * b)
  abs (G a) = G (abs a)
  signum (G a) = G (signum a)
  fromInteger = G . fromInteger
  negate (G a) = G (negate a)
instance Fractional G where
  recip (G a) = G (recip a)
  fromRational = G . fromRational

upTo :: Integral a => a -> [a]
upTo n = [1 .. n]

main :: IO ()
main = do
  -- toEnum at Word64/Word: the bound literal wrapped to -1
  print (toEnum 5 :: Word64, toEnum 0 :: Word, toEnum maxBound :: Word64)
  -- the wired Double recip and pi under Data.Ratio
  print (recip (8 :: Double), pi :: Double, 2 ^^ (-3 :: Int) :: Double, recip (3 % 4 :: Rational))
  -- Ratio Int at the bounds: GHC's (%), reduce and recip
  print (3 % (minBound :: Int), (minBound :: Int) % (-1), (-3) % (minBound :: Int))
  print (recip ((minBound :: Int) % 3), denominator (6 % (minBound :: Int)), numerator ((-4) % (-6) :: Ratio Int))
  print ((1 % 3 + 1 % 6 :: Rational), (2 % 3) / (4 % (-9)) :: Rational, recip ((-2) % 5 :: Rational))
  -- Enum class defaults
  print (succ (N 5), pred (N 5), take 3 [N 7 ..], take 3 [N 1, N 4 ..], [N 2 .. N 4], [N 9, N 6 .. N 1])
  -- Fractional class defaults
  print (recip (F 4), G 3 / G 4)
