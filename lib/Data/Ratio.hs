module Data.Ratio
  ( Ratio, Rational, (%), numerator, denominator
  ) where

infixl 7 %

--  Polymorphic exact fractions over any Integral type, as in base;
--  Rational is the Integer case. Invariant: denominator positive,
--  fraction reduced.
data Ratio a = a :% a

type Rational = Ratio Integer

--  Transcribed from GHC.Real (M146 review): (%) moves the sign onto
--  the numerator FIRST and reduce divides with quot by the gcd. The
--  earlier div-by-(gcd * signum d) form agreed for Integer but, with
--  Int now wrapping, divided minBound by -1 (an Overflow) where
--  GHC's `3 % (minBound :: Int)` is (-3) % (-9223372036854775808).
reduceR :: Integral a => a -> a -> Ratio a
reduceR _ 0 = error "Ratio has zero denominator"
reduceR x y = quot x d :% quot y d
  where
    d = gcd x y

(%) :: Integral a => a -> a -> Ratio a
(%) x y = reduceR (x * signum y) (abs y)

numerator :: Ratio a -> a
numerator (n :% _) = n

denominator :: Ratio a -> a
denominator (_ :% d) = d

--  Reduced form makes equality componentwise.
instance Eq a => Eq (Ratio a) where
  (a :% b) == (c :% d) = a == c && b == d

instance Integral a => Ord (Ratio a) where
  compare (a :% b) (c :% d) = compare (a * d) (c * b)

instance Show a => Show (Ratio a) where
  showsPrec p (n :% d) s =
    showParen (p > 7)
      (\t -> showsPrec 8 n (" % " ++ showsPrec 8 d t)) s

instance Integral a => Num (Ratio a) where
  (a :% b) + (c :% d) = reduceR (a * d + c * b) (b * d)
  (a :% b) - (c :% d) = reduceR (a * d - c * b) (b * d)
  (a :% b) * (c :% d) = reduceR (a * c) (b * d)
  negate (a :% b) = negate a :% b
  abs (a :% b) = abs a :% b
  signum (a :% _) = signum a :% 1
  fromInteger n = fromInteger n :% 1

instance Integral a => Fractional (Ratio a) where
  (a :% b) / (c :% d) = (a * d) % (b * c)
  recip (a :% b)
    | a == 0 = error "Ratio has zero denominator"
    | a < 0 = negate b :% negate a
    | otherwise = b :% a
  fromRational (n :% d) = fromInteger n % fromInteger d
