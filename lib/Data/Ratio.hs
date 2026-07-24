module Data.Ratio
  ( Ratio, Rational, (%), numerator, denominator
  ) where

infixl 7 %

--  Polymorphic exact fractions over any Integral type, as in base;
--  Rational is the Integer case. Invariant: denominator positive,
--  fraction reduced.
data Ratio a = a :% a

type Rational = Ratio Integer

reduceR :: Integral a => a -> a -> Ratio a
reduceR _ 0 = error "Ratio has zero denominator"
reduceR n d = div n g :% div d g
  where
    g = gcd n d * signum d

(%) :: Integral a => a -> a -> Ratio a
(%) n d = reduceR n d

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
  (a :% b) / (c :% d) = reduceR (a * d) (b * c)
  recip (a :% b) = reduceR b a
  fromRational (n :% d) = fromInteger n % fromInteger d
