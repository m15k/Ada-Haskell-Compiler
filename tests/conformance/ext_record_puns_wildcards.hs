{-# LANGUAGE RecordWildCards, NamedFieldPuns #-}
-- RecordWildCards and NamedFieldPuns, always on in AHC (M148).
data P = P { px :: Int, py :: Int, name :: String } deriving Show
data Box = Box { inner :: P, label :: String } deriving Show

mk :: Int -> Int -> P
mk px py = let name = "pt" in P{..}

norm :: P -> Int
norm P{..} = px * px + py * py

shiftX :: P -> P
shiftX p@P{px} = p { px = px + 1 }

rename :: String -> P -> P
rename name p = p { name }

describe :: Box -> String
describe Box{inner = P{name, ..}, ..} = label ++ ":" ++ name ++ show (px + py)

partial :: Int -> P
partial px = let py = 0 in P{..}

main :: IO ()
main = do
  print (mk 3 4, norm (mk 3 4))
  print (shiftX (mk 1 2), rename "renamed" (mk 0 0))
  putStrLn (describe (Box (mk 5 6) "box"))
  print (px (partial 9), py (partial 9))
