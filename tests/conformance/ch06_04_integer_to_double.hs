-- Report 6.4: fromInteger at Double must round the exact Integer
-- value once, to nearest-even - not accumulate per-limb rounding.
-- Fuzzer find (M76, seed 57): the naive limb loop drifted by ulps
-- on values a few bits past 53.
main :: IO ()
main = do
  print ((fromIntegral ((product (172 : [53, 24465659807378177351, 722])) :: Integer)) :: Double)
  print ((fromIntegral ((2 ^ 64 + 1) :: Integer)) :: Double)
  print ((fromIntegral ((2 ^ 64 - 1) :: Integer)) :: Double)
  print ((fromIntegral ((9007199254740993) :: Integer)) :: Double)
  print ((fromIntegral (negate (123456789012345678901234567890) :: Integer)) :: Double)
  print ((fromIntegral ((10 ^ 300) :: Integer)) :: Double)
