-- The AHC Prelude (Phase 4): standard definitions compiled by AHC
-- itself ahead of every user module. Class/type signatures and the
-- numeric primitives stay wired in AHC.Builtins / AHC.Prelude_Core;
-- everything here is ordinary Haskell 2010 checked by the compiler.

data Either a b = Left a | Right b deriving (Eq, Ord)

-- Maybe / Either utilities ------------------------------------------

maybe :: b -> (a -> b) -> Maybe a -> b
maybe d _ Nothing = d
maybe _ f (Just x) = f x

fromMaybe :: a -> Maybe a -> a
fromMaybe d Nothing = d
fromMaybe _ (Just x) = x

isJust :: Maybe a -> Bool
isJust Nothing = False
isJust _ = True

isNothing :: Maybe a -> Bool
isNothing Nothing = True
isNothing _ = False

either :: (a -> c) -> (b -> c) -> Either a b -> c
either f _ (Left x) = f x
either _ g (Right y) = g y

-- Tuples --------------------------------------------------------------

curry :: ((a, b) -> c) -> a -> b -> c
curry f a b = f (a, b)

uncurry :: (a -> b -> c) -> (a, b) -> c
uncurry f (a, b) = f a b

swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)

-- Lists ---------------------------------------------------------------

foldl :: (b -> a -> b) -> b -> [a] -> b
foldl _ z [] = z
foldl f z (x : xs) = foldl f (f z x) xs

reverse :: [a] -> [a]
reverse = foldl (flip (:)) []

take :: Int -> [a] -> [a]
take n xs = if n <= 0 then [] else takeGo xs
  where takeGo [] = []
        takeGo (y : ys) = y : take (n - 1) ys

drop :: Int -> [a] -> [a]
drop n xs = if n <= 0 then xs else dropGo xs
  where dropGo [] = []
        dropGo (_ : ys) = drop (n - 1) ys

replicate :: Int -> a -> [a]
replicate n x = if n <= 0 then [] else x : replicate (n - 1) x

iterate :: (a -> a) -> a -> [a]
iterate f x = x : iterate f (f x)

repeat :: a -> [a]
repeat x = x : repeat x

zip :: [a] -> [b] -> [(a, b)]
zip (a : as) (b : bs) = (a, b) : zip as bs
zip _ _ = []

zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]
zipWith f (a : as) (b : bs) = f a b : zipWith f as bs
zipWith _ _ _ = []

null :: [a] -> Bool
null [] = True
null _ = False

head :: [a] -> a
head (x : _) = x
head [] = error "Prelude.head: empty list"

tail :: [a] -> [a]
tail (_ : xs) = xs
tail [] = error "Prelude.tail: empty list"

last :: [a] -> a
last (x : xs) = if null xs then x else last xs
last [] = error "Prelude.last: empty list"

init :: [a] -> [a]
init (x : xs) = if null xs then [] else x : init xs
init [] = error "Prelude.init: empty list"

takeWhile :: (a -> Bool) -> [a] -> [a]
takeWhile _ [] = []
takeWhile p (x : xs) = if p x then x : takeWhile p xs else []

dropWhile :: (a -> Bool) -> [a] -> [a]
dropWhile _ [] = []
dropWhile p ys = if p (head ys) then dropWhile p (tail ys) else ys

sum :: Num a => [a] -> a
sum = foldl (+) 0

product :: Num a => [a] -> a
product = foldl (*) 1

maximum :: Ord a => [a] -> a
maximum (x : xs) = foldl max x xs
maximum [] = error "Prelude.maximum: empty list"

minimum :: Ord a => [a] -> a
minimum (x : xs) = foldl min x xs
minimum [] = error "Prelude.minimum: empty list"

elem :: Eq a => a -> [a] -> Bool
elem _ [] = False
elem e (x : xs) = e == x || elem e xs

notElem :: Eq a => a -> [a] -> Bool
notElem e xs = not (elem e xs)

lookup :: Eq a => a -> [(a, b)] -> Maybe b
lookup _ [] = Nothing
lookup k ((a, b) : rest) = if k == a then Just b else lookup k rest

and :: [Bool] -> Bool
and = foldl (&&) True

or :: [Bool] -> Bool
or = foldl (||) False

any :: (a -> Bool) -> [a] -> Bool
any p xs = or (map p xs)

all :: (a -> Bool) -> [a] -> Bool
all p xs = and (map p xs)

unwords :: [String] -> String
unwords [] = ""
unwords (w : ws) = if null ws then w else w ++ " " ++ unwords ws

unlines :: [String] -> String
unlines [] = ""
unlines (l : ls) = l ++ "\n" ++ unlines ls

mapM_ :: Monad m => (a -> m b) -> [a] -> m ()
mapM_ f xs = go xs
  where go [] = return ()
        go (y : ys) = f y >> go ys

sequence_ :: Monad m => [m a] -> m ()
sequence_ [] = return ()
sequence_ (m : ms) = m >> sequence_ ms

gcd :: Integer -> Integer -> Integer
gcd a 0 = abs a
gcd a b = gcd b (mod a b)

lcm :: Integer -> Integer -> Integer
lcm _ 0 = 0
lcm 0 _ = 0
lcm a b = abs (div (a * b) (gcd a b))

even :: Int -> Bool
even n = n `mod` 2 == 0

odd :: Int -> Bool
odd n = not (even n)

span :: (a -> Bool) -> [a] -> ([a], [a])
span p xs = (takeWhile p xs, dropWhile p xs)

break :: (a -> Bool) -> [a] -> ([a], [a])
break p xs = span (\x -> not (p x)) xs

splitAt :: Int -> [a] -> ([a], [a])
splitAt n xs = (take n xs, drop n xs)

unzip :: [(a, b)] -> ([a], [b])
unzip xs = (map fst xs, map snd xs)

foldr1 :: (a -> a -> a) -> [a] -> a
foldr1 _ [x] = x
foldr1 f (x : xs) = f x (foldr1 f xs)
foldr1 _ [] = error "foldr1: empty list"

foldl1 :: (a -> a -> a) -> [a] -> a
foldl1 f (x : xs) = foldl f x xs
foldl1 _ [] = error "foldl1: empty list"

lines :: String -> [String]
lines [] = []
lines s = case break (== '\n') s of
  (l, [])      -> [l]
  (l, _ : r)   -> l : lines r

words :: String -> [String]
words s = case dropWhile (== ' ') s of
  [] -> []
  t  -> case break (== ' ') t of
    (w, r) -> w : words r

until :: (a -> Bool) -> (a -> a) -> a -> a
until p f x = if p x then x else until p f (f x)

-- Show instances over prelude types (real elaborated dictionaries) ----

instance (Show a, Show b, Show c, Show d, Show e)
    => Show (a, b, c, d, e) where
  show (a, b, c, d, e) =
    "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ","
        ++ show d ++ "," ++ show e ++ ")"
  showsPrec _ x s = show x ++ s
  showList xs s = showsList_ xs s

instance (Show a, Show b, Show c, Show d, Show e, Show f)
    => Show (a, b, c, d, e, f) where
  show (a, b, c, d, e, f) =
    "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ","
        ++ show d ++ "," ++ show e ++ "," ++ show f ++ ")"
  showsPrec _ x s = show x ++ s
  showList xs s = showsList_ xs s

instance (Show a, Show b, Show c, Show d, Show e, Show f, Show g)
    => Show (a, b, c, d, e, f, g) where
  show (a, b, c, d, e, f, g) =
    "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ","
        ++ show d ++ "," ++ show e ++ "," ++ show f ++ ","
        ++ show g ++ ")"
  showsPrec _ x s = show x ++ s
  showList xs s = showsList_ xs s

instance (Show a, Show b, Show c) => Show (a, b, c) where
  show (a, b, c) =
    "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ")"
  showsPrec _ x s = show x ++ s
  showList xs s = showsList_ xs s

instance (Show a, Show b, Show c, Show d) => Show (a, b, c, d) where
  show (a, b, c, d) =
    "(" ++ show a ++ "," ++ show b ++ "," ++ show c ++ ","
        ++ show d ++ ")"
  showsPrec _ x s = show x ++ s
  showList xs s = showsList_ xs s

instance (Show a, Show b) => Show (a, b) where
  show (a, b) = "(" ++ show a ++ "," ++ show b ++ ")"
  showsPrec _ x s = show x ++ s
  showList xs s = showsList_ xs s

showParen :: Bool -> (String -> String) -> String -> String
showParen b p s = if b then "(" ++ p (")" ++ s) else p s

showString :: String -> String -> String
showString x s = x ++ s

shows :: Show a => a -> String -> String
shows x s = showsPrec 0 x s

showsList_ :: Show a => [a] -> String -> String
showsList_ xs s = "[" ++ goSL xs ("]" ++ s)

goSL :: Show a => [a] -> String -> String
goSL [] s = s
goSL (x : r) s = show x ++ restSL r s

restSL :: Show a => [a] -> String -> String
restSL [] s = s
restSL (x : r) s = "," ++ show x ++ restSL r s

instance Show a => Show (Maybe a) where
  showsPrec _ Nothing s = "Nothing" ++ s
  showsPrec d (Just x) s =
    showParen (d > 10) (\t -> "Just " ++ showsPrec 11 x t) s
  show x = showsPrec 0 x ""
  showList xs s = showsList_ xs s

instance (Show a, Show b) => Show (Either a b) where
  showsPrec d (Left x) s =
    showParen (d > 10) (\t -> "Left " ++ showsPrec 11 x t) s
  showsPrec d (Right y) s =
    showParen (d > 10) (\t -> "Right " ++ showsPrec 11 y t) s
  show x = showsPrec 0 x ""
  showList xs s = showsList_ xs s
