newtype D = D Double deriving Show
instance Num D where
  D a + D b = D (a+b); D a * D b = D (a*b); abs (D a) = D (abs a)
  signum (D a) = D (signum a); fromInteger = D . fromInteger; negate (D a) = D (negate a)
instance Fractional D where
  fromRational = D . fromRational; D a / D b = D (a/b)
instance Floating D where
  pi = D pi; exp (D a) = D (exp a); log (D a) = D (log a)
  sin (D a) = D (sin a); cos (D a) = D (cos a); asin (D a) = D (asin a)
  acos (D a) = D (acos a); atan (D a) = D (atan a); sinh (D a) = D (sinh a)
  cosh (D a) = D (cosh a); asinh (D a) = D 42; acosh (D a) = D (acosh a); atanh (D a) = D (atanh a)
main = print (asinh (D 1))
