data Shape = Circle Double | Rect Double Double
area (Circle r) = r * r
area (Rect w h) = w * h
classify n
  | n < 0 = "neg"
  | otherwise = "pos"
  where m = n
first (x : _) = Just x
first [] = Nothing
swap (a, b) = (b, a)
data P = P { px :: Int, py :: Int }
move p = p { px = px p + 1 }
(u, v) = (1, 2)
