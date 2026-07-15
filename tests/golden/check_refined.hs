type Percent = Int in 0 .. 100

clamp :: Int -> Percent
clamp n = if n < 0 then 0 else if n > 100 then 100 else n

scale :: Percent -> Percent -> Int
scale p q = p * q

offset :: Int in -10 .. 10
offset = let base :: Int
             base = 3
         in base + 2

weight :: Show a => a -> Int in 0 .. 60
weight x = length (show x)
