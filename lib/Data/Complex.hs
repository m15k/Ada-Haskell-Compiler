module Data.Complex
  ( Complex (..), realPart, imagPart, conjugate
  , magnitude, phase, mkPolar, cis, polar
  ) where

infix 6 :+

--  Polymorphic complex numbers, as in base: the polar family needs
--  RealFloat (atan2 lives there), which exists as a real class
--  since M69.
data Complex a = a :+ a

realPart :: Complex a -> a
realPart (x :+ _) = x

imagPart :: Complex a -> a
imagPart (_ :+ y) = y

conjugate :: Num a => Complex a -> Complex a
conjugate (x :+ y) = x :+ negate y

magnitude :: RealFloat a => Complex a -> a
magnitude (x :+ y) = sqrt (x * x + y * y)

phase :: RealFloat a => Complex a -> a
phase (x :+ y) = atan2 y x

mkPolar :: RealFloat a => a -> a -> Complex a
mkPolar r theta = (r * cos theta) :+ (r * sin theta)

cis :: RealFloat a => a -> Complex a
cis theta = cos theta :+ sin theta

polar :: RealFloat a => Complex a -> (a, a)
polar z = (magnitude z, phase z)

instance Eq a => Eq (Complex a) where
  (a :+ b) == (c :+ d) = a == c && b == d

instance Show a => Show (Complex a) where
  showsPrec p (x :+ y) s =
    showParen (p > 6)
      (\t -> showsPrec 7 x (" :+ " ++ showsPrec 7 y t)) s

instance RealFloat a => Num (Complex a) where
  (a :+ b) + (c :+ d) = (a + c) :+ (b + d)
  (a :+ b) - (c :+ d) = (a - c) :+ (b - d)
  (a :+ b) * (c :+ d) = (a * c - b * d) :+ (a * d + b * c)
  negate (a :+ b) = negate a :+ negate b
  abs z = magnitude z :+ 0
  signum (0 :+ 0) = 0 :+ 0
  signum z = (realPart z / m) :+ (imagPart z / m)
    where m = magnitude z
  fromInteger n = fromInteger n :+ 0
