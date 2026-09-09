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

-- Either a is a Functor/Applicative/Monad in its Right component,
-- as base has it (Left short-circuits).
instance Functor (Either a) where
  fmap _ (Left x) = Left x
  fmap f (Right y) = Right (f y)

instance Applicative (Either a) where
  pure x = Right x
  Left e <*> _ = Left e
  Right f <*> r = fmap f r

instance Monad (Either a) where
  return x = Right x
  Left e >>= _ = Left e
  Right x >>= k = k x

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

mapM :: Monad m => (a -> m b) -> [a] -> m [b]
mapM _ [] = return []
mapM f (x : xs) = f x >>= \y -> mapM f xs >>= \ys -> return (y : ys)

mapM_ :: Monad m => (a -> m b) -> [a] -> m ()
mapM_ f xs = go xs
  where go [] = return ()
        go (y : ys) = f y >> go ys

sequence :: Monad m => [m a] -> m [a]
sequence ms = mapM (\m -> m) ms

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

infixl 4 <$>, <$, <*>, *>, <*

(<$>) :: Functor f => (a -> b) -> f a -> f b
f <$> x = fmap f x

-- GHC's Prelude exports (<$) with Functor; ($>) stays Data.Functor's.
(<$) :: Functor f => a -> f b -> f a
(<$) x fb = fmap (\_ -> x) fb

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

-- Splits on isSpace like the Report's (Unicode-aware since the
-- string milestone F3; primIsSpaceU is the Data.Char table prim).
words :: String -> [String]
words s = case dropWhile primIsSpaceU s of
  [] -> []
  t  -> case break primIsSpaceU t of
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

-- Semigroup / Monoid (base-compat beyond the 2010 Report; the
-- string-milestone F4) ----------------------------------------------

infixr 6 <>

class Semigroup a where
  (<>) :: a -> a -> a

class Semigroup a => Monoid a where
  mempty :: a
  mappend :: a -> a -> a
  mappend = (<>)
  mconcat :: [a] -> a
  mconcat = foldr (<>) mempty

instance Semigroup [a] where
  (<>) = (++)

instance Monoid [a] where
  mempty = []

instance Semigroup Text where
  (<>) = primTextAppend

instance Monoid Text where
  mempty = primTextPack ""

instance Semigroup Ordering where
  LT <> _ = LT
  EQ <> y = y
  GT <> _ = GT

instance Monoid Ordering where
  mempty = EQ

instance Semigroup a => Semigroup (Maybe a) where
  Nothing <> b = b
  a <> Nothing = a
  Just x <> Just y = Just (x <> y)

instance Semigroup a => Monoid (Maybe a) where
  mempty = Nothing

instance Semigroup () where
  _ <> _ = ()

instance Monoid () where
  mempty = ()

-- Exceptions (Report 9; docs/exceptions-design-note.md) ------------
-- IOError is ABSTRACT: the value lives in the runtime (a wired
-- opaque type, like Text), System.IO.Error is the API, and this
-- Show text is exactly what the runtime prints for an uncaught one.

type IOError = IOException

ioError :: IOError -> IO a
ioError e = primThrowIO (primExcFromIO e)

userError :: String -> IOError
userError s = primMkIOError 7 "" s Nothing

instance Show IOException where
  showsPrec _ e =
      showFile . showLoc . showString (typeName (primIoeType e)) . showDesc
    where
      loc = primIoeLocation e
      desc = primIoeDescription e
      showFile = case primIoeFilename e of
        Just f -> showString f . showString ": "
        Nothing -> id
      showLoc = if null loc then id else showString loc . showString ": "
      showDesc = if null desc then id
                 else showString " (" . showString desc . showString ")"
      -- the runtime's IOErrorType table, in declaration order
      typeName t = case t of
        0 -> "already exists"
        1 -> "does not exist"
        2 -> "resource busy"
        3 -> "resource exhausted"
        4 -> "end of file"
        5 -> "illegal operation"
        6 -> "permission denied"
        7 -> "user error"
        8 -> "inappropriate type"
        10 -> "invalid argument"
        _ -> "failed"

instance Eq IOException where
  a == b = primIoeType a == primIoeType b
        && primIoeLocation a == primIoeLocation b
        && primIoeDescription a == primIoeDescription b
        && primIoeFilename a == primIoeFilename b

-- Fixed-width integers (Data.Int / Data.Word, M139) -----------------
-- Int8..Word64 share Int's runtime representation - an exact, promoting
-- integer - so every arithmetic result is Int's result NARROWED to the
-- width by primNarrow, which is what makes them wrap like GHC's; the
-- literal `200 :: Int8` is -56 and `read "300" :: Word8` is 44. Eq, Ord
-- and Show are wired (Int's, correct on narrowed values). The error
-- texts are GHC 9.4.8's. This block is GENERATED (one shape, eight
-- types): edit the generator's shape in the M139 plan, not one copy.

type Word = Word64

overflowQuot_ :: Bool -> Bool -> a -> a
overflowQuot_ isMin isNegOne r =
  if isMin && isNegOne then primThrow (primExcArith 0) else r

narrowInt8_ :: Int -> Int8
narrowInt8_ x = primFixCast (primNarrow 8 1 x)

toInt8_ :: Int8 -> Int
toInt8_ = primFixCast

instance Num Int8 where
  a + b = narrowInt8_ (toInt8_ a + toInt8_ b)
  a - b = narrowInt8_ (toInt8_ a - toInt8_ b)
  a * b = narrowInt8_ (toInt8_ a * toInt8_ b)
  negate a = narrowInt8_ (negate (toInt8_ a))
  abs a = narrowInt8_ (abs (toInt8_ a))
  signum a = narrowInt8_ (signum (toInt8_ a))
  fromInteger i = narrowInt8_ (fromInteger i)

instance Bounded Int8 where
  minBound = narrowInt8_ (-128)
  maxBound = narrowInt8_ (127)

instance Real Int8 where
  toRational a = toRational (toInt8_ a)

instance Enum Int8 where
  toEnum i =
    if i < -128 || i > 127
      then error ("Enum.toEnum{Int8}: tag (" ++ show i
                  ++ ") is outside of bounds (-128,127)")
      else narrowInt8_ i
  fromEnum a = toInt8_ a
  succ a = if a == maxBound
             then error "Enum.succ{Int8}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int8}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowInt8_ [toInt8_ a .. toInt8_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowInt8_ [toInt8_ a, toInt8_ b .. toInt8_ c]

instance Integral Int8 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt8_ (-1))
               (narrowInt8_ (quot (toInt8_ a) (toInt8_ b)))
  rem a b = overflowQuot_ (a == minBound) (b == narrowInt8_ (-1))
              (narrowInt8_ (rem (toInt8_ a) (toInt8_ b)))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt8_ (-1))
              (narrowInt8_ (div (toInt8_ a) (toInt8_ b)))
  mod a b = overflowQuot_ (a == minBound) (b == narrowInt8_ (-1))
              (narrowInt8_ (mod (toInt8_ a) (toInt8_ b)))
  toInteger a = toInteger (toInt8_ a)

instance Read Int8 where
  readsPrec _ s = [(narrowInt8_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowInt16_ :: Int -> Int16
narrowInt16_ x = primFixCast (primNarrow 16 1 x)

toInt16_ :: Int16 -> Int
toInt16_ = primFixCast

instance Num Int16 where
  a + b = narrowInt16_ (toInt16_ a + toInt16_ b)
  a - b = narrowInt16_ (toInt16_ a - toInt16_ b)
  a * b = narrowInt16_ (toInt16_ a * toInt16_ b)
  negate a = narrowInt16_ (negate (toInt16_ a))
  abs a = narrowInt16_ (abs (toInt16_ a))
  signum a = narrowInt16_ (signum (toInt16_ a))
  fromInteger i = narrowInt16_ (fromInteger i)

instance Bounded Int16 where
  minBound = narrowInt16_ (-32768)
  maxBound = narrowInt16_ (32767)

instance Real Int16 where
  toRational a = toRational (toInt16_ a)

instance Enum Int16 where
  toEnum i =
    if i < -32768 || i > 32767
      then error ("Enum.toEnum{Int16}: tag (" ++ show i
                  ++ ") is outside of bounds (-32768,32767)")
      else narrowInt16_ i
  fromEnum a = toInt16_ a
  succ a = if a == maxBound
             then error "Enum.succ{Int16}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int16}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowInt16_ [toInt16_ a .. toInt16_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowInt16_ [toInt16_ a, toInt16_ b .. toInt16_ c]

instance Integral Int16 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt16_ (-1))
               (narrowInt16_ (quot (toInt16_ a) (toInt16_ b)))
  rem a b = overflowQuot_ (a == minBound) (b == narrowInt16_ (-1))
              (narrowInt16_ (rem (toInt16_ a) (toInt16_ b)))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt16_ (-1))
              (narrowInt16_ (div (toInt16_ a) (toInt16_ b)))
  mod a b = overflowQuot_ (a == minBound) (b == narrowInt16_ (-1))
              (narrowInt16_ (mod (toInt16_ a) (toInt16_ b)))
  toInteger a = toInteger (toInt16_ a)

instance Read Int16 where
  readsPrec _ s = [(narrowInt16_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowInt32_ :: Int -> Int32
narrowInt32_ x = primFixCast (primNarrow 32 1 x)

toInt32_ :: Int32 -> Int
toInt32_ = primFixCast

instance Num Int32 where
  a + b = narrowInt32_ (toInt32_ a + toInt32_ b)
  a - b = narrowInt32_ (toInt32_ a - toInt32_ b)
  a * b = narrowInt32_ (toInt32_ a * toInt32_ b)
  negate a = narrowInt32_ (negate (toInt32_ a))
  abs a = narrowInt32_ (abs (toInt32_ a))
  signum a = narrowInt32_ (signum (toInt32_ a))
  fromInteger i = narrowInt32_ (fromInteger i)

instance Bounded Int32 where
  minBound = narrowInt32_ (-2147483648)
  maxBound = narrowInt32_ (2147483647)

instance Real Int32 where
  toRational a = toRational (toInt32_ a)

instance Enum Int32 where
  toEnum i =
    if i < -2147483648 || i > 2147483647
      then error ("Enum.toEnum{Int32}: tag (" ++ show i
                  ++ ") is outside of bounds (-2147483648,2147483647)")
      else narrowInt32_ i
  fromEnum a = toInt32_ a
  succ a = if a == maxBound
             then error "Enum.succ{Int32}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int32}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowInt32_ [toInt32_ a .. toInt32_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowInt32_ [toInt32_ a, toInt32_ b .. toInt32_ c]

instance Integral Int32 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt32_ (-1))
               (narrowInt32_ (quot (toInt32_ a) (toInt32_ b)))
  rem a b = overflowQuot_ (a == minBound) (b == narrowInt32_ (-1))
              (narrowInt32_ (rem (toInt32_ a) (toInt32_ b)))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt32_ (-1))
              (narrowInt32_ (div (toInt32_ a) (toInt32_ b)))
  mod a b = overflowQuot_ (a == minBound) (b == narrowInt32_ (-1))
              (narrowInt32_ (mod (toInt32_ a) (toInt32_ b)))
  toInteger a = toInteger (toInt32_ a)

instance Read Int32 where
  readsPrec _ s = [(narrowInt32_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowInt64_ :: Int -> Int64
narrowInt64_ x = primFixCast (primNarrow 64 1 x)

toInt64_ :: Int64 -> Int
toInt64_ = primFixCast

instance Num Int64 where
  a + b = narrowInt64_ (toInt64_ a + toInt64_ b)
  a - b = narrowInt64_ (toInt64_ a - toInt64_ b)
  a * b = narrowInt64_ (toInt64_ a * toInt64_ b)
  negate a = narrowInt64_ (negate (toInt64_ a))
  abs a = narrowInt64_ (abs (toInt64_ a))
  signum a = narrowInt64_ (signum (toInt64_ a))
  fromInteger i = narrowInt64_ (fromInteger i)

instance Bounded Int64 where
  minBound = narrowInt64_ (-9223372036854775808)
  maxBound = narrowInt64_ (9223372036854775807)

instance Real Int64 where
  toRational a = toRational (toInt64_ a)

instance Enum Int64 where
  toEnum i =
    if i < -9223372036854775808 || i > 9223372036854775807
      then error ("Enum.toEnum{Int64}: tag (" ++ show i
                  ++ ") is outside of bounds (-9223372036854775808,9223372036854775807)")
      else narrowInt64_ i
  fromEnum a = toInt64_ a
  succ a = if a == maxBound
             then error "Enum.succ{Int64}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int64}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowInt64_ [toInt64_ a .. toInt64_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowInt64_ [toInt64_ a, toInt64_ b .. toInt64_ c]

instance Integral Int64 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt64_ (-1))
               (narrowInt64_ (quot (toInt64_ a) (toInt64_ b)))
  rem a b = overflowQuot_ (a == minBound) (b == narrowInt64_ (-1))
              (narrowInt64_ (rem (toInt64_ a) (toInt64_ b)))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt64_ (-1))
              (narrowInt64_ (div (toInt64_ a) (toInt64_ b)))
  mod a b = overflowQuot_ (a == minBound) (b == narrowInt64_ (-1))
              (narrowInt64_ (mod (toInt64_ a) (toInt64_ b)))
  toInteger a = toInteger (toInt64_ a)

instance Read Int64 where
  readsPrec _ s = [(narrowInt64_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowWord8_ :: Int -> Word8
narrowWord8_ x = primFixCast (primNarrow 8 0 x)

toWord8_ :: Word8 -> Int
toWord8_ = primFixCast

instance Num Word8 where
  a + b = narrowWord8_ (toWord8_ a + toWord8_ b)
  a - b = narrowWord8_ (toWord8_ a - toWord8_ b)
  a * b = narrowWord8_ (toWord8_ a * toWord8_ b)
  negate a = narrowWord8_ (negate (toWord8_ a))
  abs a = narrowWord8_ (abs (toWord8_ a))
  signum a = narrowWord8_ (signum (toWord8_ a))
  fromInteger i = narrowWord8_ (fromInteger i)

instance Bounded Word8 where
  minBound = narrowWord8_ (0)
  maxBound = narrowWord8_ (255)

instance Real Word8 where
  toRational a = toRational (toWord8_ a)

instance Enum Word8 where
  toEnum i =
    if i < 0 || i > 255
      then error ("Enum.toEnum{Word8}: tag (" ++ show i
                  ++ ") is outside of bounds (0,255)")
      else narrowWord8_ i
  fromEnum a = toWord8_ a
  succ a = if a == maxBound
             then error "Enum.succ{Word8}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word8}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowWord8_ [toWord8_ a .. toWord8_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowWord8_ [toWord8_ a, toWord8_ b .. toWord8_ c]

instance Integral Word8 where
  quot a b = overflowQuot_ (False) (b == narrowWord8_ (-1))
               (narrowWord8_ (quot (toWord8_ a) (toWord8_ b)))
  rem a b = overflowQuot_ (False) (b == narrowWord8_ (-1))
              (narrowWord8_ (rem (toWord8_ a) (toWord8_ b)))
  div a b = overflowQuot_ (False) (b == narrowWord8_ (-1))
              (narrowWord8_ (div (toWord8_ a) (toWord8_ b)))
  mod a b = overflowQuot_ (False) (b == narrowWord8_ (-1))
              (narrowWord8_ (mod (toWord8_ a) (toWord8_ b)))
  toInteger a = toInteger (toWord8_ a)

instance Read Word8 where
  readsPrec _ s = [(narrowWord8_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowWord16_ :: Int -> Word16
narrowWord16_ x = primFixCast (primNarrow 16 0 x)

toWord16_ :: Word16 -> Int
toWord16_ = primFixCast

instance Num Word16 where
  a + b = narrowWord16_ (toWord16_ a + toWord16_ b)
  a - b = narrowWord16_ (toWord16_ a - toWord16_ b)
  a * b = narrowWord16_ (toWord16_ a * toWord16_ b)
  negate a = narrowWord16_ (negate (toWord16_ a))
  abs a = narrowWord16_ (abs (toWord16_ a))
  signum a = narrowWord16_ (signum (toWord16_ a))
  fromInteger i = narrowWord16_ (fromInteger i)

instance Bounded Word16 where
  minBound = narrowWord16_ (0)
  maxBound = narrowWord16_ (65535)

instance Real Word16 where
  toRational a = toRational (toWord16_ a)

instance Enum Word16 where
  toEnum i =
    if i < 0 || i > 65535
      then error ("Enum.toEnum{Word16}: tag (" ++ show i
                  ++ ") is outside of bounds (0,65535)")
      else narrowWord16_ i
  fromEnum a = toWord16_ a
  succ a = if a == maxBound
             then error "Enum.succ{Word16}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word16}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowWord16_ [toWord16_ a .. toWord16_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowWord16_ [toWord16_ a, toWord16_ b .. toWord16_ c]

instance Integral Word16 where
  quot a b = overflowQuot_ (False) (b == narrowWord16_ (-1))
               (narrowWord16_ (quot (toWord16_ a) (toWord16_ b)))
  rem a b = overflowQuot_ (False) (b == narrowWord16_ (-1))
              (narrowWord16_ (rem (toWord16_ a) (toWord16_ b)))
  div a b = overflowQuot_ (False) (b == narrowWord16_ (-1))
              (narrowWord16_ (div (toWord16_ a) (toWord16_ b)))
  mod a b = overflowQuot_ (False) (b == narrowWord16_ (-1))
              (narrowWord16_ (mod (toWord16_ a) (toWord16_ b)))
  toInteger a = toInteger (toWord16_ a)

instance Read Word16 where
  readsPrec _ s = [(narrowWord16_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowWord32_ :: Int -> Word32
narrowWord32_ x = primFixCast (primNarrow 32 0 x)

toWord32_ :: Word32 -> Int
toWord32_ = primFixCast

instance Num Word32 where
  a + b = narrowWord32_ (toWord32_ a + toWord32_ b)
  a - b = narrowWord32_ (toWord32_ a - toWord32_ b)
  a * b = narrowWord32_ (toWord32_ a * toWord32_ b)
  negate a = narrowWord32_ (negate (toWord32_ a))
  abs a = narrowWord32_ (abs (toWord32_ a))
  signum a = narrowWord32_ (signum (toWord32_ a))
  fromInteger i = narrowWord32_ (fromInteger i)

instance Bounded Word32 where
  minBound = narrowWord32_ (0)
  maxBound = narrowWord32_ (4294967295)

instance Real Word32 where
  toRational a = toRational (toWord32_ a)

instance Enum Word32 where
  toEnum i =
    if i < 0 || i > 4294967295
      then error ("Enum.toEnum{Word32}: tag (" ++ show i
                  ++ ") is outside of bounds (0,4294967295)")
      else narrowWord32_ i
  fromEnum a = toWord32_ a
  succ a = if a == maxBound
             then error "Enum.succ{Word32}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word32}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowWord32_ [toWord32_ a .. toWord32_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowWord32_ [toWord32_ a, toWord32_ b .. toWord32_ c]

instance Integral Word32 where
  quot a b = overflowQuot_ (False) (b == narrowWord32_ (-1))
               (narrowWord32_ (quot (toWord32_ a) (toWord32_ b)))
  rem a b = overflowQuot_ (False) (b == narrowWord32_ (-1))
              (narrowWord32_ (rem (toWord32_ a) (toWord32_ b)))
  div a b = overflowQuot_ (False) (b == narrowWord32_ (-1))
              (narrowWord32_ (div (toWord32_ a) (toWord32_ b)))
  mod a b = overflowQuot_ (False) (b == narrowWord32_ (-1))
              (narrowWord32_ (mod (toWord32_ a) (toWord32_ b)))
  toInteger a = toInteger (toWord32_ a)

instance Read Word32 where
  readsPrec _ s = [(narrowWord32_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]

narrowWord64_ :: Int -> Word64
narrowWord64_ x = primFixCast (primNarrow 64 0 x)

toWord64_ :: Word64 -> Int
toWord64_ = primFixCast

instance Num Word64 where
  a + b = narrowWord64_ (toWord64_ a + toWord64_ b)
  a - b = narrowWord64_ (toWord64_ a - toWord64_ b)
  a * b = narrowWord64_ (toWord64_ a * toWord64_ b)
  negate a = narrowWord64_ (negate (toWord64_ a))
  abs a = narrowWord64_ (abs (toWord64_ a))
  signum a = narrowWord64_ (signum (toWord64_ a))
  fromInteger i = narrowWord64_ (fromInteger i)

instance Bounded Word64 where
  minBound = narrowWord64_ (0)
  maxBound = narrowWord64_ (18446744073709551615)

instance Real Word64 where
  toRational a = toRational (toWord64_ a)

instance Enum Word64 where
  toEnum i =
    if i < 0 || i > 18446744073709551615
      then error ("Enum.toEnum{Word64}: tag (" ++ show i
                  ++ ") is outside of bounds (0,18446744073709551615)")
      else narrowWord64_ i
  fromEnum a = toWord64_ a
  succ a = if a == maxBound
             then error "Enum.succ{Word64}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word64}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = map narrowWord64_ [toWord64_ a .. toWord64_ b]
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = map narrowWord64_ [toWord64_ a, toWord64_ b .. toWord64_ c]

instance Integral Word64 where
  quot a b = overflowQuot_ (False) (b == narrowWord64_ (-1))
               (narrowWord64_ (quot (toWord64_ a) (toWord64_ b)))
  rem a b = overflowQuot_ (False) (b == narrowWord64_ (-1))
              (narrowWord64_ (rem (toWord64_ a) (toWord64_ b)))
  div a b = overflowQuot_ (False) (b == narrowWord64_ (-1))
              (narrowWord64_ (div (toWord64_ a) (toWord64_ b)))
  mod a b = overflowQuot_ (False) (b == narrowWord64_ (-1))
              (narrowWord64_ (mod (toWord64_ a) (toWord64_ b)))
  toInteger a = toInteger (toWord64_ a)

instance Read Word64 where
  readsPrec _ s = [(narrowWord64_ (integerToInt_ i), r) | (i, r) <- readsInteger_ s]
