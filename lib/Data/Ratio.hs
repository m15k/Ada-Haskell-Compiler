module Data.Ratio
  ( Rational, (%), numerator, denominator
  ) where

infixl 7 %

data Rational = Integer :% Integer

--  Invariant: denominator positive, fraction reduced.
reduceR :: Integer -> Integer -> Rational
reduceR _ 0 = error "Ratio has zero denominator"
reduceR n d = div n g :% div d g
  where
    g = gcd n d * signum d

(%) :: Integer -> Integer -> Rational
(%) n d = reduceR n d

numerator :: Rational -> Integer
numerator (n :% _) = n

denominator :: Rational -> Integer
denominator (_ :% d) = d

instance Eq Rational where
  (a :% b) == (c :% d) = a == c && b == d

instance Ord Rational where
  compare (a :% b) (c :% d) = compare (a * d) (c * b)

instance Show Rational where
  showsPrec p (n :% d) s =
    showParen (p > 7)
      (\t -> showsPrec 8 n (" % " ++ showsPrec 8 d t)) s

instance Num Rational where
  (a :% b) + (c :% d) = reduceR (a * d + c * b) (b * d)
  (a :% b) - (c :% d) = reduceR (a * d - c * b) (b * d)
  (a :% b) * (c :% d) = reduceR (a * c) (b * d)
  negate (a :% b) = negate a :% b
  abs (a :% b) = abs a :% b
  signum (a :% _) = signum a :% 1
  fromInteger n = n :% 1

instance Fractional Rational where
  (a :% b) / (c :% d) = reduceR (a * d) (b * c)
  recip (a :% b) = reduceR b a
