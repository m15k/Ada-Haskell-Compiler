data Color = Red | Green | Blue

name :: Color -> String
name Red = "red"
name Green = "green"

both :: Color -> Color -> Int
both Red _ = 1
both _ Blue = 2

full :: Color -> Int
full Red = 1
full Green = 2
full Blue = 3

dup :: Color -> Int
dup Red = 1
dup Green = 2
dup Blue = 3
dup Red = 4

guarded :: Int -> Int
guarded n
  | n > 0 = 1
  | otherwise = 0

partialG :: Int -> Int
partialG n
  | n > 0 = 1

classify :: Maybe Int -> String
classify m =
  case m of
    Nothing -> "none"
    Just 0 -> "zero"

pairs :: (Bool, Bool) -> Int
pairs (True, True) = 1
pairs (True, False) = 2
pairs (False, True) = 3

lists :: [Int] -> Int
lists [] = 0
lists (x : _) = x

main :: IO ()
main = putStrLn (name Red)
