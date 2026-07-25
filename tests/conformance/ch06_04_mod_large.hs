-- Report 6.4.2: div/mod floor toward negative infinity, at every
-- magnitude. The textbook floored-mod idiom ((x`rem`y)+y)`rem`y
-- OVERFLOWS when both operands are large positives; the fuzzer
-- (M83, seed 6215) caught it as a wrong gcd and a mis-reduced
-- Rational, several layers above the arithmetic.
main :: IO ()
main = do
  print (7483135014491189818 `mod` 8242269370533867258 :: Integer)
  print (gcd 7483135014491189818 8242269370533867258 :: Integer)
  print (map (\(a, b) -> a `mod` b)
    [ (9223372036854775806, 9223372036854775807)
    , (-9223372036854775806, 9223372036854775807)
    , (9223372036854775806, -9223372036854775807)
    , (-9223372036854775806, -9223372036854775807)
    , (17, 5), (-17, 5), (17, -5), (-17, -5), (0, 7) ] :: [Integer])
  print (map (\(a, b) -> a `div` b)
    [ (7483135014491189818, 8242269370533867258)
    , (-9223372036854775806, 9223372036854775807)
    , (17, 5), (-17, 5), (17, -5), (-17, -5) ] :: [Integer])
  print ((7483135014491189818 * 3) `mod` 8242269370533867258 :: Integer)
