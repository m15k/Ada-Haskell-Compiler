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

-- Report 9.1: infixl 9 !! (the fixity is wired in AHC.Fixity).
(!!) :: [a] -> Int -> a
xs !! n = if n < 0 then error "Prelude.!!: negative index" else indexGo_ xs n

indexGo_ :: [a] -> Int -> a
indexGo_ [] _ = error "Prelude.!!: index too large"
indexGo_ (x : xs) n = if n == 0 then x else indexGo_ xs (n - 1)

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

gcd :: Integral a => a -> a -> a
gcd a 0 = abs a
gcd a b = gcd b (mod a b)

lcm :: Integral a => a -> a -> a
lcm _ 0 = 0
lcm 0 _ = 0
lcm a b = abs (div (a * b) (gcd a b))

even :: Integral a => a -> Bool
even n = n `mod` 2 == 0

odd :: Integral a => a -> Bool
odd n = not (even n)

fromIntegral :: (Integral a, Num b) => a -> b
fromIntegral n = fromInteger (toInteger n)

infixr 8 ^, ^^

(^) :: (Num a, Integral b) => a -> b -> a
x ^ n
  | n < 0 = error "Negative exponent"
  | otherwise = go n
  where
    go k =
      if k == 0
        then 1
        else
          let h = go (div k 2)
              s = h * h
          in if mod k 2 == 0 then s else s * x

(^^) :: (Fractional a, Integral b) => a -> b -> a
x ^^ n = if n >= 0 then x ^ n else recip (x ^ negate n)

-- Enum at Char and Double: dictionary method bodies, bound by the
-- compiler into the instance dictionaries (trailing underscore =
-- internal). Char rides ord/chr over the Int instance; Double
-- follows Report 6.3.4's numeric enumeration (the half-step rule).
charSucc_ :: Char -> Char
charSucc_ c = chr (ord c + 1)

charPred_ :: Char -> Char
charPred_ c = chr (ord c - 1)

charEF_ :: Char -> [Char]
charEF_ a = charEFT_ a '\1114111'

charEFTh_ :: Char -> Char -> [Char]
charEFTh_ a b =
  map chr
    (enumFromThenTo (ord a) (ord b)
       (if ord b >= ord a then 1114111 else 0))

charEFT_ :: Char -> Char -> [Char]
charEFT_ a b = map chr [ord a .. ord b]

charEFThT_ :: Char -> Char -> Char -> [Char]
charEFThT_ a b c = map chr (enumFromThenTo (ord a) (ord b) (ord c))

dblSucc_ :: Double -> Double
dblSucc_ x = x + 1.0

dblPred_ :: Double -> Double
dblPred_ x = x - 1.0

dblToE_ :: Int -> Double
dblToE_ i = fromIntegral i

dblFromE_ :: Double -> Int
dblFromE_ x = fromInteger (truncate x)

dblPF_ :: Double -> (Integer, Double)
dblPF_ x = let n = truncate x in (n, x - fromInteger n)

dblEF_ :: Double -> [Double]
dblEF_ n = n : dblEF_ (n + 1)

-- k-indexed (n + k*delta), matching GHC's Double enumeration: the
-- chained recurrence accumulates rounding ([0.1,0.2..] would show
-- 0.4000000000000001 where GHC prints 0.4).
dblEFTh_ :: Double -> Double -> [Double]
dblEFTh_ n m = goTh_ n (m - n) 0

goTh_ :: Double -> Double -> Int -> [Double]
goTh_ n delta k =
  (n + fromIntegral k * delta) : goTh_ n delta (k + 1)

dblEFT_ :: Double -> Double -> [Double]
dblEFT_ n m = takeWhile (\x -> x <= m + 1 / 2) (dblEF_ n)

dblEFThT_ :: Double -> Double -> Double -> [Double]
dblEFThT_ n n' m =
  takeWhile
    (if n' >= n
       then \x -> x <= m + (n' - n) / 2
       else \x -> x >= m + (n' - n) / 2)
    (dblEFTh_ n n')

infixl 4 <$>, <*>, *>, <*

(<$>) :: Functor f => (a -> b) -> f a -> f b
f <$> x = fmap f x

-- Applicative, as GHC's base has it (the Report predates it); an
-- ordinary source class over the wired Functor.
class Functor f => Applicative f where
  pure :: a -> f a
  (<*>) :: f (a -> b) -> f a -> f b
  liftA2 :: (a -> b -> c) -> f a -> f b -> f c
  liftA2 f x y = fmap f x <*> y
  (*>) :: f a -> f b -> f b
  (*>) x y = liftA2 (\_ b -> b) x y
  (<*) :: f a -> f b -> f a
  (<*) x y = liftA2 (\a _ -> a) x y

instance Applicative Maybe where
  pure x = Just x
  Nothing <*> _ = Nothing
  Just f <*> mx = fmap f mx

instance Applicative [] where
  pure x = [x]
  fs <*> xs = concatMap (\f -> map f xs) fs

instance Applicative IO where
  pure x = return x
  mf <*> mx = mf >>= \f -> mx >>= \x -> return (f x)

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

-- Read ----------------------------------------------------------------
-- Report 9.1 exports Read (..), reads and read from the Prelude, so the
-- class and its instances live here rather than in Text.Read, which is
-- now a facade over these definitions. Keeping the class here is also
-- what lets `deriving Read` work without importing Text.Read (the
-- compiler binds readsEnum_ by name -- AHC.Prelude_Core).
-- The Prelude has no imports, so the three character predicates Read
-- needs are private ASCII copies of the Data.Char ones.

class Read a where
  readsPrec :: Int -> String -> [(a, String)]

reads :: Read a => String -> [(a, String)]
reads s = readsPrec 0 s

read :: Read a => String -> a
read s =
  case [x | (x, t) <- reads s, allSpace_ t] of
    [x] -> x
    _   -> error "Prelude.read: no parse"

isSpace_ :: Char -> Bool
isSpace_ c = c == ' ' || c == '\t' || c == '\n' || c == '\r'

isDigit_ :: Char -> Bool
isDigit_ c = c >= '0' && c <= '9'

isIdChar_ :: Char -> Bool
isIdChar_ c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || isDigit_ c || c == '\''

allSpace_ :: String -> Bool
allSpace_ [] = True
allSpace_ (c : cs) = isSpace_ c && allSpace_ cs

skipSpace_ :: String -> String
skipSpace_ = dropWhile isSpace_

--  Derived-Read support (bound by the compiler for deriving Read on
--  enumerations): match one maximal identifier token against the
--  constructor table.
readsEnum_ :: [(String, a)] -> Int -> String -> [(a, String)]
readsEnum_ table _ s =
  case span isIdChar_ (skipSpace_ s) of
    (tok, rest) -> [ (v, rest) | (nm, v) <- table, nm == tok ]

--  Integers: optional parenthesized negative, per the Report's lex.
readsInteger_ :: String -> [(Integer, String)]
readsInteger_ s0 =
  case skipSpace_ s0 of
    ('-' : t) -> [(negate n, r) | (n, r) <- readsNat_ t]
    ('(' : t) ->
      [ (n, r2)
      | (n, r) <- readsInteger_ t
      , (')' : r2) <- [skipSpace_ r]
      ]
    t -> readsNat_ t

readsNat_ :: String -> [(Integer, String)]
readsNat_ s =
  case span isDigit_ s of
    ([], _)     -> []
    (digits, r) ->
      [(foldl (\a c -> a * 10 + digitVal_ c) 0 digits, r)]

digitVal_ :: Char -> Integer
digitVal_ c =
  if isDigit_ c then toInteger (fromEnum c - fromEnum '0')
  else error "Prelude.read: not a digit"

instance Read Integer where
  readsPrec _ s = readsInteger_ s

instance Read Int where
  readsPrec _ s =
    [(integerToInt_ n, r) | (n, r) <- readsInteger_ s]

integerToInt_ :: Integer -> Int
integerToInt_ n = fromInteger n

instance Read Bool where
  readsPrec _ s =
    case skipSpace_ s of
      ('T' : 'r' : 'u' : 'e' : r) -> [(True, r)]
      ('F' : 'a' : 'l' : 's' : 'e' : r) -> [(False, r)]
      _ -> []

instance Read a => Read [a] where
  readsPrec _ s =
    case skipSpace_ s of
      ('[' : t) ->
        case skipSpace_ t of
          (']' : r) -> [([], r)]
          _         -> readItems t
      _ -> []
    where
      readItems u =
        [ (x : xs, r2)
        | (x, r) <- readsPrec 0 u
        , (xs, r2) <- readRest (skipSpace_ r)
        ]
      readRest (',' : u) = readItems u
      readRest (']' : u) = [([], u)]
      readRest _ = []

instance (Read a, Read b) => Read (a, b) where
  readsPrec _ s =
    case skipSpace_ s of
      ('(' : t) ->
        [ ((x, y), r4)
        | (x, r) <- readsPrec 0 t
        , (',' : r2) <- [skipSpace_ r]
        , (y, r3) <- readsPrec 0 r2
        , (')' : r4) <- [skipSpace_ r3]
        ]
      _ -> []
