module Data.Complex
  ( Complex (..), realPart, imagPart, conjugate
  , magnitude, phase, mkPolar, cis, polar
  ) where

infix 6 :+

data Complex = Double :+ Double

realPart :: Complex -> Double
realPart (x :+ _) = x

imagPart :: Complex -> Double
imagPart (_ :+ y) = y

conjugate :: Complex -> Complex
conjugate (x :+ y) = x :+ negate y

magnitude :: Complex -> Double
magnitude (x :+ y) = sqrt (x * x + y * y)

phase :: Complex -> Double
phase (x :+ y) = atan2 y x

mkPolar :: Double -> Double -> Complex
mkPolar r theta = (r * cos theta) :+ (r * sin theta)

cis :: Double -> Complex
cis theta = cos theta :+ sin theta

polar :: Complex -> (Double, Double)
polar z = (magnitude z, phase z)

instance Eq Complex where
  (a :+ b) == (c :+ d) = a == c && b == d

instance Show Complex where
  showsPrec p (x :+ y) s =
    showParen (p > 6)
      (\t -> showsPrec 7 x (" :+ " ++ showsPrec 7 y t)) s

instance Num Complex where
  (a :+ b) + (c :+ d) = (a + c) :+ (b + d)
  (a :+ b) - (c :+ d) = (a - c) :+ (b - d)
  (a :+ b) * (c :+ d) = (a * c - b * d) :+ (a * d + b * c)
  negate (a :+ b) = negate a :+ negate b
  abs z = magnitude z :+ 0
  signum (0 :+ 0) = 0 :+ 0
  signum z = (realPart z / m) :+ (imagPart z / m)
    where m = magnitude z
  fromInteger n = fromIntegral2 n :+ 0

--  Integer -> Double (fromIntegral is Int -> Double in AHC).
fromIntegral2 :: Integer -> Double
fromIntegral2 n = fromInteger n
