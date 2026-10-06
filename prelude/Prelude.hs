-- The export list is what GHC 9.4.8's Prelude exports (`ghc -e ':browse
-- Prelude'`), and it is the only part of this file a USER module sees:
-- a module compiled from lib/ or $AHC_LIB resolves the implicit Prelude
-- through the whole file (library code is base's internals), a user
-- module through this list. scripts/check_prelude_exports.sh diffs the
-- list against GHC's and fails on any difference not documented here.
--
-- ABSENT-NAMES: MonadFail lex floatRadix floatDigits floatRange decodeFloat
--   encodeFloat exponent significand scaleFloat isDenormalized isIEEE
-- NOT-METHODS: <$ divMod quotRem mapM sequence sequenceA
--   (GHC class methods that are plain functions here; EXCLUSIONS)
-- (the lines above are read by scripts/check_prelude_exports.sh). GHC
-- exports these, AHC's Prelude does not define them:
--   MonadFail   (AHC's Monad carries `fail` itself; do-notation's
--                failing patterns call that method)
--   lex         (Report 9's lexer; derived Read uses lexTok_ instead)
--   the RealFloat internals floatRadix, floatDigits, floatRange,
--   decodeFloat, encodeFloat, exponent, significand, scaleFloat,
--   isDenormalized, isIEEE (RealFloat is the useful IEEE subset)

module Prelude
  ( -- types and classes
    Applicative
  , Bool (..)
  , Bounded
  , Char
  , Double
  , Either (..)
  , Enum
  , Eq
  , FilePath
  , Float
  , Floating
  , Foldable
  , Fractional
  , Functor
  , IO
  , IOError
  , Int
  , Integer
  , Integral
  , Maybe (..)
  , Monad
  , Monoid
  , Num
  , Ord
  , Ordering (..)
  , Rational
  , Read
  , Real
  , RealFloat
  , RealFrac
  , Semigroup
  , Show
  , String
  , Traversable
  , ReadS
  , ShowS
  , Word
  , -- values, operators and class methods
    (!!)
  , ($)
  , ($!)
  , (&&)
  , (++)
  , (.)
  , (<$>)
  , pure
  , (<*>)
  , (*>)
  , (<*)
  , minBound
  , maxBound
  , succ
  , pred
  , toEnum
  , fromEnum
  , enumFrom
  , enumFromThen
  , enumFromTo
  , enumFromThenTo
  , (==)
  , (/=)
  , pi
  , exp
  , log
  , sqrt
  , (**)
  , logBase
  , sin
  , cos
  , tan
  , asin
  , acos
  , atan
  , sinh
  , cosh
  , tanh
  , foldr
  , foldl
  , foldr1
  , foldl1
  , null
  , length
  , elem
  , maximum
  , minimum
  , sum
  , product
  , (/)
  , recip
  , fromRational
  , fmap
  , (<$)
  , quot
  , rem
  , div
  , mod
  , quotRem
  , divMod
  , toInteger
  , (>>=)
  , (>>)
  , return
  , fail
  , mempty
  , mappend
  , mconcat
  , (+)
  , (-)
  , (*)
  , negate
  , abs
  , signum
  , fromInteger
  , compare
  , (<)
  , (<=)
  , (>)
  , (>=)
  , max
  , min
  , readsPrec
  , readList
  , toRational
  , isNaN
  , isInfinite
  , isNegativeZero
  , atan2
  , properFraction
  , truncate
  , round
  , ceiling
  , floor
  , (<>)
  , showsPrec
  , show
  , showList
  , traverse
  , sequenceA
  , mapM
  , sequence
  , (^)
  , (^^)
  , all
  , and
  , any
  , break
  , concat
  , concatMap
  , const
  , curry
  , cycle
  , drop
  , dropWhile
  , either
  , error
  , even
  , filter
  , flip
  , fromIntegral
  , fst
  , gcd
  , getChar
  , getContents
  , getLine
  , head
  , id
  , init
  , interact
  , ioError
  , iterate
  , last
  , lcm
  , lines
  , lookup
  , map
  , mapM_
  , maybe
  , not
  , notElem
  , odd
  , or
  , otherwise
  , print
  , putChar
  , putStr
  , putStrLn
  , read
  , readFile
  , readIO
  , readLn
  , readParen
  , reads
  , realToFrac
  , repeat
  , replicate
  , reverse
  , seq
  , sequence_
  , showParen
  , showString
  , shows
  , snd
  , span
  , splitAt
  , subtract
  , tail
  , take
  , takeWhile
  , uncurry
  , undefined
  , unlines
  , until
  , unwords
  , unzip
  , userError
  , words
  , zip
  , zipWith
  , (||)
  , scanl
  , scanl1
  , scanr
  , scanr1
  , zip3
  , unzip3
  , zipWith3
  , writeFile
  , appendFile
  , (=<<)
  , showChar
  , asTypeOf
  , foldMap
  , errorWithoutStackTrace
  , asinh
  , acosh
  , atanh
  ) where

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

foldlList_ :: (b -> a -> b) -> b -> [a] -> b
foldlList_ _ z [] = z
foldlList_ f z (x : xs) = foldlList_ f (f z x) xs

reverse :: [a] -> [a]
reverse = foldlList_ (flip (:)) []

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

nullList_ :: [a] -> Bool
nullList_ [] = True
nullList_ _ = False

head :: [a] -> a
head (x : _) = x
head [] = error "Prelude.head: empty list"

tail :: [a] -> [a]
tail (_ : xs) = xs
tail [] = error "Prelude.tail: empty list"

last :: [a] -> a
last (x : xs) = if nullList_ xs then x else last xs
last [] = error "Prelude.last: empty list"

init :: [a] -> [a]
init (x : xs) = if nullList_ xs then [] else x : init xs
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

sumList_ :: Num a => [a] -> a
sumList_ = foldlList_ (+) 0

productList_ :: Num a => [a] -> a
productList_ = foldlList_ (*) 1

maximumList_ :: Ord a => [a] -> a
maximumList_ (x : xs) = foldlList_ max x xs
maximumList_ [] = error "Prelude.maximum: empty list"

minimumList_ :: Ord a => [a] -> a
minimumList_ (x : xs) = foldlList_ min x xs
minimumList_ [] = error "Prelude.minimum: empty list"

elemList_ :: Eq a => a -> [a] -> Bool
elemList_ _ [] = False
elemList_ e (x : xs) = e == x || elemList_ e xs

lookup :: Eq a => a -> [(a, b)] -> Maybe b
lookup _ [] = Nothing
lookup k ((a, b) : rest) = if k == a then Just b else lookup k rest

andList_ :: [Bool] -> Bool
andList_ = foldlList_ (&&) True

orList_ :: [Bool] -> Bool
orList_ = foldlList_ (||) False

unwords :: [String] -> String
unwords [] = ""
unwords (w : ws) = if nullList_ ws then w else w ++ " " ++ unwords ws

unlines :: [String] -> String
unlines [] = ""
unlines (l : ls) = l ++ "\n" ++ unlines ls

mapM :: Monad m => (a -> m b) -> [a] -> m [b]
mapM _ [] = return []
mapM f (x : xs) = f x >>= \y -> mapM f xs >>= \ys -> return (y : ys)

mapMList__ :: Monad m => (a -> m b) -> [a] -> m ()
mapMList__ f xs = go xs
  where go [] = return ()
        go (y : ys) = f y >> go ys

sequence :: Monad m => [m a] -> m [a]
sequence ms = mapM (\m -> m) ms

sequenceList__ :: Monad m => [m a] -> m ()
sequenceList__ [] = return ()
sequenceList__ (m : ms) = m >> sequenceList__ ms

-- Report 6.4.2, transcribed: gcd works on the absolute values with
-- rem, and lcm divides before it multiplies - with a wrapping Int the
-- order shows (gcd minBound 6 is -2, as GHC's).
gcd :: Integral a => a -> a -> a
gcd x y = gcd' (abs x) (abs y)
  where gcd' a 0 = a
        gcd' a b = gcd' b (a `rem` b)

lcm :: Integral a => a -> a -> a
lcm _ 0 = 0
lcm 0 _ = 0
lcm x y = abs ((x `quot` (gcd x y)) * y)

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
charSucc_ c =
  if ord c == 1114111
    then errorWithoutStackTrace "Prelude.Enum.Char.succ: bad argument"
    else chr (ord c + 1)

charPred_ :: Char -> Char
charPred_ c =
  if ord c == 0
    then errorWithoutStackTrace "Prelude.Enum.Char.pred: bad argument"
    else chr (ord c - 1)

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

-- Integer enumeration (M146): Prelude source, so it is lazy and exact
-- for bignums; the C range primitives are Int-only. The stepped forms
-- follow base's numericEnumFromThenTo for Integral types: stop past
-- the bound in the stride's direction; a zero stride repeats while
-- n <= m, as the Report's enumFromThenTo does.
integerSucc_ :: Integer -> Integer
integerSucc_ n = n + 1

integerPred_ :: Integer -> Integer
integerPred_ n = n - 1

integerEF_ :: Integer -> [Integer]
integerEF_ n = n : integerEF_ (n + 1)

integerEFTh_ :: Integer -> Integer -> [Integer]
integerEFTh_ n m = go n
  where d = m - n
        go x = x : go (x + d)

-- A range whose bounds fit a machine word runs on Int's chunked C
-- generator: a small Integer and an Int are the same node, so the
-- cast is exact (and keeps [1 .. n] :: [Integer] as fast as before
-- M146 moved Integer's enumeration here).
integerEFT_ :: Integer -> Integer -> [Integer]
integerEFT_ n m
  | integerIsWord_ n && integerIsWord_ m =
      primFixCast (enumFromTo (primFixCast n :: Int) (primFixCast m :: Int))
  | otherwise = if n > m then [] else go n
  where go x = x : (if x == m then [] else go (x + 1))

integerIsWord_ :: Integer -> Bool
integerIsWord_ x = x >= -9223372036854775808 && x <= 9223372036854775807

integerEFThT_ :: Integer -> Integer -> Integer -> [Integer]
integerEFThT_ n n' m
  | integerIsWord_ n && integerIsWord_ n' && integerIsWord_ m =
      primFixCast (enumFromThenTo (primFixCast n :: Int) (primFixCast n' :: Int)
                                  (primFixCast m :: Int))
  | d >= 0    = if n > m then [] else up n
  | otherwise = if n < m then [] else down n
  where d = n' - n
        up x = x : (let y = x + d in if y > m then [] else up y)
        down x = x : (let y = x + d in if y < m then [] else down y)

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
  fs <*> xs = concatMapList_ (\f -> map f xs) fs

instance Applicative IO where
  pure x = return x
  mf <*> mx = mf >>= \f -> mx >>= \x -> return (f x)

-- The function type `(->) r` - the reader - as base has it (M142
-- made `(->)` an ordinary type constructor for instance heads).
instance Functor ((->) r) where
  fmap f g = \x -> f (g x)

instance Applicative ((->) r) where
  pure x = \_ -> x
  f <*> g = \x -> f x (g x)
  liftA2 q f g = \x -> q (f x) (g x)

instance Monad ((->) r) where
  return x = \_ -> x
  f >>= k = \r -> k (f r) r

span :: (a -> Bool) -> [a] -> ([a], [a])
span p xs = (takeWhile p xs, dropWhile p xs)

break :: (a -> Bool) -> [a] -> ([a], [a])
break p xs = span (\x -> not (p x)) xs

splitAt :: Int -> [a] -> ([a], [a])
splitAt n xs = (take n xs, drop n xs)

unzip :: [(a, b)] -> ([a], [b])
unzip xs = (map fst xs, map snd xs)

foldr1List_ :: (a -> a -> a) -> [a] -> a
foldr1List_ _ [x] = x
foldr1List_ f (x : xs) = f x (foldr1List_ f xs)
foldr1List_ _ [] = error "foldr1: empty list"

foldl1List_ :: (a -> a -> a) -> [a] -> a
foldl1List_ f (x : xs) = foldlList_ f x xs
foldl1List_ _ [] = error "foldl1: empty list"

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

-- Bounded tuples, componentwise, for every tuple size AHC has.
instance (Bounded a, Bounded b) => Bounded (a, b) where
  minBound = (minBound, minBound)
  maxBound = (maxBound, maxBound)

instance (Bounded a, Bounded b, Bounded c) => Bounded (a, b, c) where
  minBound = (minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound)

instance (Bounded a, Bounded b, Bounded c, Bounded d) => Bounded (a, b, c, d) where
  minBound = (minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound)

instance (Bounded a, Bounded b, Bounded c, Bounded d, Bounded e) => Bounded (a, b, c, d, e) where
  minBound = (minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Bounded a, Bounded b, Bounded c, Bounded d, Bounded e, Bounded f) => Bounded (a, b, c, d, e, f) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

instance (Bounded a, Bounded b, Bounded c, Bounded d, Bounded e, Bounded f, Bounded g) => Bounded (a, b, c, d, e, f, g) where
  minBound = (minBound, minBound, minBound, minBound, minBound, minBound, minBound)
  maxBound = (maxBound, maxBound, maxBound, maxBound, maxBound, maxBound, maxBound)

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

--  Report 9.1's Read has TWO methods. readList exists so that the
--  list instance can be specialised at Char: `read "\"ann\""` has to
--  yield a String, not a list of character literals, and a record
--  field of type String is the commonest thing derived Read meets.
class Read a where
  readsPrec :: Int -> String -> [(a, String)]
  readList :: String -> [([a], String)]
  readList = readListDefault_ readsPrec

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
--  readParen False, not a bare identifier match: GHC's derived Read
--  accepts "(Red)" and "((Red))" for a nullary constructor, and so
--  must this - the non-enumeration path gets the same through the
--  readParen the compiler generates.
readsEnum_ :: [(String, a)] -> Int -> String -> [(a, String)]
readsEnum_ table _ s =
  readParen False
    (\r -> case span isIdChar_ (skipSpace_ r) of
             (tok, rest) -> [ (v, rest) | (nm, v) <- table, nm == tok ])
    s

--  Derived-Read support for NON-enumerations (Report 11.4 and
--  Appendix D). The generated reader is a CHAIN of ReadS steps, so
--  the compiler composes these combinators instead of building a
--  parser: one step per expected lexeme and one per field, ending in
--  retReadS_ applied to the rebuilt constructor. Derived Read must be
--  the exact inverse of derived Show, so the precedences here mirror
--  AHC.Prelude_Core's Derive_Show: 11 under a prefix constructor, 10
--  either side of an infix one, 0 inside record braces.

bindReadS_ :: [(a, String)] -> (a -> String -> [(b, String)])
           -> [(b, String)]
bindReadS_ xs k = concatMapList_ (\(v, r) -> k v r) xs

retReadS_ :: a -> String -> [(a, String)]
retReadS_ v r = [(v, r)]

--  Match ONE expected lexeme after whitespace. Identifier and
--  operator tokens have to end at a lexeme boundary, or "C" would
--  match the "C" inside "Cons" and leave "ons" behind.
lexTok_ :: String -> String -> [((), String)]
lexTok_ tok s =
  case stripPre_ tok (skipSpace_ s) of
    Nothing -> []
    Just r  -> if boundaryOk_ tok r then [((), r)] else []

stripPre_ :: String -> String -> Maybe String
stripPre_ [] r = Just r
stripPre_ _ [] = Nothing
stripPre_ (c : cs) (d : ds) = if c == d then stripPre_ cs ds else Nothing

boundaryOk_ :: String -> String -> Bool
boundaryOk_ tok r =
  case r of
    [] -> True
    (c : _) ->
      let l = lastCh_ tok
      in if isIdChar_ l then not (isIdChar_ c)
         else if isSymCh_ l then not (isSymCh_ c)
         else True

lastCh_ :: String -> Char
lastCh_ [] = ' '
lastCh_ [c] = c
lastCh_ (_ : cs) = lastCh_ cs

isSymCh_ :: Char -> Bool
isSymCh_ c = elemList_ c "!#$%&*+./<=>?@\\^|-~:"

--  Report 9.1. `readParen True` demands the parentheses, `False`
--  accepts them or not - which is what makes a nullary constructor
--  read out of "(C)" as GHC's derived instance does.
readParen :: Bool -> (String -> [(a, String)]) -> String -> [(a, String)]
readParen b g = if b then mandatory_ else optional_
  where
    optional_ r = g r ++ mandatory_ r
    mandatory_ r =
      bindReadS_ (lexTok_ "(" r) (\_ s ->
      bindReadS_ (readParen False g s) (\x t ->
      bindReadS_ (lexTok_ ")" t) (\_ u ->
      retReadS_ x u)))

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
      [(foldlList_ (\a c -> a * 10 + digitVal_ c) 0 digits, r)]

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

--  The Report's bracketed-list reader, over an element reader passed
--  explicitly so the compiler can hand it the readsPrec it just built
--  for a derived instance.
readListDefault_ :: (Int -> String -> [(a, String)])
                 -> String -> [([a], String)]
readListDefault_ rp s =
  case skipSpace_ s of
    ('[' : t) ->
      case skipSpace_ t of
        (']' : r) -> [([], r)]
        _         -> readItems t
    _ -> []
  where
    readItems u =
      [ (x : xs, r2)
      | (x, r) <- rp 0 u
      , (xs, r2) <- readRest (skipSpace_ r)
      ]
    readRest (',' : u) = readItems u
    readRest (']' : u) = [([], u)]
    readRest _ = []

--  Report 9.1: the list instance IS the element's readList, which is
--  what makes String read as a quoted literal.
instance Read a => Read [a] where
  readsPrec _ s = readList s

instance Read Char where
  readsPrec _ s =
    case skipSpace_ s of
      ('\'' : t) ->
        [ (c, r)
        | (c, q) <- readCharEsc_ t
        , ('\'' : r) <- [q]
        ]
      _ -> []
  readList s =
    case skipSpace_ s of
      ('"' : t) -> readStrLit_ t
      _ -> []

--  One character of a literal, escapes included. Derived Show emits
--  \\ \' \" \n \t \r and a decimal \NNN for anything else
--  unprintable, so reading those back round-trips show.
readCharEsc_ :: String -> [(Char, String)]
readCharEsc_ [] = []
readCharEsc_ ('\\' : c : r) =
  case c of
    'n'  -> [('\n', r)]
    't'  -> [('\t', r)]
    'r'  -> [('\r', r)]
    '\\' -> [('\\', r)]
    '\'' -> [('\'', r)]
    '"'  -> [('"', r)]
    _    -> if isDigit_ c
            then case span isDigit_ (c : r) of
                   (ds, r2) ->
                     [(toEnum (fromInteger
                        (foldlList_ (\a d -> a * 10 + digitVal_ d)
                                    0 ds)), r2)]
            else []
readCharEsc_ (c : r) = [(c, r)]

readStrLit_ :: String -> [(String, String)]
readStrLit_ ('"' : r) = [("", r)]
readStrLit_ s =
  [ (c : cs, r2)
  | (c, r) <- readCharEsc_ s
  , (cs, r2) <- readStrLit_ r
  ]

--  Written over the derived-Read combinators, in exactly the shape
--  the compiler generates for a hand-written equivalent.
instance Read a => Read (Maybe a) where
  readsPrec d s =
    readParen False
      (\r -> bindReadS_ (lexTok_ "Nothing" r)
               (\_ r1 -> retReadS_ Nothing r1)) s
    ++ readParen (d > 10)
         (\r -> bindReadS_ (lexTok_ "Just" r) (\_ r1 ->
                bindReadS_ (readsPrec 11 r1) (\x r2 ->
                retReadS_ (Just x) r2))) s

instance (Read a, Read b) => Read (Either a b) where
  readsPrec d s =
    readParen (d > 10)
      (\r -> bindReadS_ (lexTok_ "Left" r) (\_ r1 ->
             bindReadS_ (readsPrec 11 r1) (\x r2 ->
             retReadS_ (Left x) r2))) s
    ++ readParen (d > 10)
         (\r -> bindReadS_ (lexTok_ "Right" r) (\_ r1 ->
                bindReadS_ (readsPrec 11 r1) (\x r2 ->
                retReadS_ (Right x) r2))) s

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
  mconcat = foldrList_ (<>) mempty

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
      showLoc = if nullList_ loc then id else showString loc . showString ": "
      showDesc = if nullList_ desc then id
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
        11 -> "unsatisfied constraints"
        _ -> "failed"

instance Eq IOException where
  a == b = primIoeType a == primIoeType b
        && primIoeLocation a == primIoeLocation b
        && primIoeDescription a == primIoeDescription b
        && primIoeFilename a == primIoeFilename b

-- read at Double (M141) --------------------------------------------
-- The digits are parsed here and converted by the runtime through the
-- same exact path a float LITERAL takes, so `read "0.1" :: Double` and
-- the literal 0.1 are the same value and both agree with GHC. Two RPN
-- calculators off GitHub wanted this (docs/repos-to-try.md).

readsDouble_ :: String -> [(Double, String)]
readsDouble_ s0 =
  case skipSpace_ s0 of
    ('-' : t) -> [(negate v, r) | (v, r) <- unsigned t]
    ('(' : t) ->
      [ (v, r2)
      | (v, r) <- readsDouble_ t
      , (')' : r2) <- [skipSpace_ r]
      ]
    t -> unsigned t
  where
    unsigned t =
      case span isDigit_ t of
        ([], _) -> []
        (whole, rest) ->
          let (frac, rest2) = fracPart rest
              (ex, rest3) = expPart rest2
              digits = whole ++ frac
              mant = foldlList_ (\a c -> a * 10 + toInteger (fromEnum c - 48)) 0 digits
          in [(primDoubleFromDec mant (ex - lengthList_ frac), rest3)]
    fracPart ('.' : u) =
      case span isDigit_ u of
        ([], _) -> ("", '.' : u)
        (ds, r) -> (ds, r)
    fracPart u = ("", u)
    expPart (c : u) =
      if c == 'e' || c == 'E'
        then case u of
               ('-' : v) -> negExp v (c : u)
               ('+' : v) -> posExp v (c : u)
               _ -> posExp u (c : u)
        else ("" `seq` 0, c : u)
    expPart u = (0, u)
    negExp v orig = case span isDigit_ v of
                      ([], _) -> (0, orig)
                      (ds, r) -> (negate (digitsToInt_ ds), r)
    posExp v orig = case span isDigit_ v of
                      ([], _) -> (0, orig)
                      (ds, r) -> (digitsToInt_ ds, r)

digitsToInt_ :: String -> Int
digitsToInt_ = foldlList_ (\a c -> a * 10 + (fromEnum c - 48)) 0

instance Read Double where
  readsPrec _ s = readsDouble_ s

-- Report 9 Prelude entries that were only in System.IO (M141: three
-- repos wanted `interact` or `getChar` with no import at all).

interact :: (String -> String) -> IO ()
interact f = getContents >>= \s -> putStr (f s)

-- stdin is handle 0 in the runtime's registry; System.IO's `stdin`
-- is the same handle behind an abstract type. (`writeFile` and
-- `appendFile` stay in System.IO, where `Handle`, `IOMode` and the
-- bracket-based `withFile` they are built on live - the one place
-- AHC's Prelude is smaller than the Report's, recorded in
-- EXCLUSIONS.)
getChar :: IO Char
getChar = primHGetChar 0

putChar :: Char -> IO ()
putChar c = putStr [c]

-- Report 9: `readIO` fails in the IO monad rather than calling
-- `error`, and distinguishes no parse from an ambiguous one.
readIO :: Read a => String -> IO a
readIO s =
  case [x | (x, t) <- reads s, allSpace_ t] of
    [x] -> return x
    []  -> ioError (userError "Prelude.readIO: no parse")
    _   -> ioError (userError "Prelude.readIO: ambiguous parse")

readLn :: Read a => IO a
readLn = getLine >>= readIO

cycle :: [a] -> [a]
cycle [] = error "Prelude.cycle: empty list"
cycle xs = xs' where xs' = xs ++ xs'


-- Foldable (base-compat beyond the 2010 Report, like Applicative and
-- Semigroup). The 2010 Prelude's list functions are list-ONLY; base's
-- are `Foldable t => ...`, which is why `elem x aSet` is ordinary code
-- in the wild and was a type error here (thibaudmichaud/lambda-calculus
-- folds over Data.Set through the Prelude).
--
-- Minimal definition `foldMap | foldr`, as in base: foldMap defaults to
-- a foldr, foldr to a foldMap into the (unexported) Endo_ monoid; every
-- other method defaults to a foldr too. The containers override the
-- cheap ones (Set.length is its size annotation, not a traversal). The
-- list instance forwards to the list-monomorphic originals, kept under
-- *List_ names, so `length someList` costs exactly what it always did
-- and the desugarer still has a concatMap needing no dictionary.
-- `toList` is not exported by GHC's Prelude: toListF_ is the internal
-- spelling; the public name is Data.Foldable's.
class Foldable t where
  foldr :: (a -> b -> b) -> b -> t a -> b
  null :: t a -> Bool
  length :: t a -> Int
  foldl :: (b -> a -> b) -> b -> t a -> b
  elem :: Eq a => a -> t a -> Bool
  sum :: Num a => t a -> a
  product :: Num a => t a -> a
  maximum :: Ord a => t a -> a
  minimum :: Ord a => t a -> a
  foldMap :: Monoid m => (a -> m) -> t a -> m
  foldr1 :: (a -> a -> a) -> t a -> a
  foldl1 :: (a -> a -> a) -> t a -> a

  foldMap f t = foldr (\x acc -> mappend (f x) acc) mempty t
  foldr f z t = appEndo_ (foldMap (\x -> Endo_ (f x)) t) z
  null t = foldr (\_ _ -> False) True t
  length t = foldr (\_ n -> n + 1) 0 t
  foldl f z t = foldlList_ f z (toListF_ t)
  elem e t = elemList_ e (toListF_ t)
  sum t = sumList_ (toListF_ t)
  product t = productList_ (toListF_ t)
  maximum t = maximumList_ (toListF_ t)
  minimum t = minimumList_ (toListF_ t)
  foldr1 f t = foldr1Default_ f t
  foldl1 f t = foldl1Default_ f t

newtype Endo_ b = Endo_ (b -> b)

appEndo_ :: Endo_ b -> b -> b
appEndo_ (Endo_ f) = f

instance Semigroup (Endo_ b) where
  Endo_ f <> Endo_ g = Endo_ (\x -> f (g x))

instance Monoid (Endo_ b) where
  mempty = Endo_ (\x -> x)

foldr1Default_ :: Foldable t => (a -> a -> a) -> t a -> a
foldr1Default_ f t =
  case foldr (\x m -> Just (case m of
                              Nothing -> x
                              Just y -> f x y)) Nothing t of
    Just r -> r
    Nothing -> errorWithoutStackTrace "foldr1: empty structure"

foldl1Default_ :: Foldable t => (a -> a -> a) -> t a -> a
foldl1Default_ f t =
  case foldl (\m y -> Just (case m of
                              Nothing -> y
                              Just x -> f x y)) Nothing t of
    Just r -> r
    Nothing -> errorWithoutStackTrace "foldl1: empty structure"

toListF_ :: Foldable t => t a -> [a]
toListF_ t = foldr (:) [] t

instance Foldable [] where
  foldr = foldrList_
  null = nullList_
  length = lengthList_
  foldl = foldlList_
  elem = elemList_
  sum = sumList_
  product = productList_
  maximum = maximumList_
  minimum = minimumList_
  foldr1 = foldr1List_
  foldl1 = foldl1List_

instance Foldable Maybe where
  foldr _ z Nothing = z
  foldr f z (Just x) = f x z
  null Nothing = True
  null (Just _) = False
  length Nothing = 0
  length (Just _) = 1

-- base folds over the RIGHT component only, so `length (Left e)` is 0
-- and `length (Right x)` is 1.
instance Foldable (Either a) where
  foldr _ z (Left _) = z
  foldr f z (Right x) = f x z
  null (Left _) = True
  null (Right _) = False
  length (Left _) = 0
  length (Right _) = 1

-- The Foldable-general functions that are not methods (base keeps
-- these as plain functions over the class, and so does this).
notElem :: (Foldable t, Eq a) => a -> t a -> Bool
notElem e t = not (elem e t)

concat :: Foldable t => t [a] -> [a]
concat t = concatList_ (toListF_ t)

concatMap :: Foldable t => (a -> [b]) -> t a -> [b]
concatMap f t = concatMapList_ f (toListF_ t)

and :: Foldable t => t Bool -> Bool
and t = andList_ (toListF_ t)

or :: Foldable t => t Bool -> Bool
or t = orList_ (toListF_ t)

any :: Foldable t => (a -> Bool) -> t a -> Bool
any p t = orList_ (map p (toListF_ t))

all :: Foldable t => (a -> Bool) -> t a -> Bool
all p t = andList_ (map p (toListF_ t))


mapM_ :: (Foldable t, Monad m) => (a -> m b) -> t a -> m ()
mapM_ f t = mapMList__ f (toListF_ t)

sequence_ :: (Foldable t, Monad m) => t (m a) -> m ()
sequence_ t = sequenceList__ (toListF_ t)

-- Traversable (base-compat beyond the 2010 Report, like Applicative
-- and Semigroup): `traverse` and `sequenceA` only. The Report's
-- `mapM`/`sequence` stay the list-specific Prelude functions above, so
-- this class does not carry them - the divergence is in EXCLUSIONS.
class Functor t => Traversable t where
  traverse :: Applicative f => (a -> f b) -> t a -> f (t b)

-- GHC has sequenceA as a second method whose default is `traverse id`
-- (and traverse's default is `sequenceA . fmap f`). One method and one
-- function are indistinguishable to a user of the class, and they do
-- not need mutually recursive defaults to typecheck.
sequenceA :: (Traversable t, Applicative f) => t (f a) -> f (t a)
sequenceA xs = traverse id xs

instance Traversable [] where
  traverse f = foldrList_ (\x acc -> pure (:) <*> f x <*> acc) (pure [])

instance Traversable Maybe where
  traverse _ Nothing = pure Nothing
  traverse f (Just x) = pure Just <*> f x

instance Traversable (Either a) where
  traverse _ (Left e) = pure (Left e)
  traverse f (Right x) = pure Right <*> f x


-- Fixed-width integers (Data.Int / Data.Word, M139) -----------------
-- Int8..Word64 compute in Integer - exact and promoting - and every
-- arithmetic result is NARROWED to the width by primNarrow, which is
-- what makes them wrap like GHC's (M146: the carrier was Int until Int
-- itself started to wrap; a Word64 above 2^63 needs the exact value); the
-- literal `200 :: Int8` is -56 and `read "300" :: Word8` is 44. Eq, Ord
-- and Show are wired (Int's, correct on narrowed values). Enumeration
-- goes through Integer, since a Word64 above 2^63 is a bignum that
-- Int's range primitives cannot see; quot/div of minBound by -1 raise
-- Overflow like GHC's, rem/mod return 0 like GHC's. The error texts are
-- GHC 9.4.8's. This block is GENERATED (one shape, eight types): edit
-- the generator's shape in the M139 plan, not one copy.

type Word = Word64

overflowQuot_ :: Bool -> Bool -> a -> a
overflowQuot_ isMin isNegOne r =
  if isMin && isNegOne then primThrow (primExcArith 0) else r

-- Lazy enumeration for the fixed-width types: one element at a time
-- (Int's range primitives build the whole list, and a Word64 above
-- 2^63 is a bignum they cannot see), the stride in Integer so a step
-- of 2^64 - 1 cannot overflow; a zero stride repeats forever, as the
-- Report's enumFromThenTo does.
fixedEnumFromTo_ :: (Ord a, Num a) => a -> a -> [a]
fixedEnumFromTo_ a b =
  if a > b then [] else go a
  where go x = x : (if x == b then [] else go (x + 1))

fixedEnumFromThenTo_ :: (Integral a) => a -> a -> a -> [a]
fixedEnumFromThenTo_ a b c =
  let ia = toInteger a
      d = toInteger b - ia
      ic = toInteger c
      go i = if (if d >= 0 then i > ic else i < ic) then []
             else fromInteger i : go (i + d)
  in if d == 0 then (if ia > ic then [] else repeat a) else go ia

-- Report 6.4.1: subtract x y = y - x, through the type's own Num
-- instance (a wired binding to Int's primitive ignored it: `subtract 1
-- (0 :: Word16)` gave -1 - the M139 review).
subtract :: Num a => a -> a -> a
subtract x y = y - x

-- Report 6.4.2 / 6.4.3 (Prelude functions, not class methods here).
quotRem :: Integral a => a -> a -> (a, a)
quotRem a b = (quot a b, rem a b)

divMod :: Integral a => a -> a -> (a, a)
divMod a b = (div a b, mod a b)

realToFrac :: (Real a, Fractional b) => a -> b
realToFrac x = fromRational (toRational x)

narrowInt8_ :: Integer -> Int8
narrowInt8_ x = primFixCast (primNarrow 8 1 (primFixCast x))

toInt8_ :: Int8 -> Integer
toInt8_ = primFixCast

instance Num Int8 where
  a + b = narrowInt8_ (toInt8_ a + toInt8_ b)
  a - b = narrowInt8_ (toInt8_ a - toInt8_ b)
  a * b = narrowInt8_ (toInt8_ a * toInt8_ b)
  negate a = narrowInt8_ (negate (toInt8_ a))
  abs a = narrowInt8_ (abs (toInt8_ a))
  signum a = narrowInt8_ (signum (toInt8_ a))
  fromInteger i = narrowInt8_ i

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
      else narrowInt8_ (toInteger i)
  fromEnum a = fromInteger (toInt8_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Int8}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int8}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Int8 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt8_ (-1))
               (narrowInt8_ (quot (toInt8_ a) (toInt8_ b)))
  rem a b = narrowInt8_ (rem (toInt8_ a) (toInt8_ b))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt8_ (-1))
              (narrowInt8_ (div (toInt8_ a) (toInt8_ b)))
  mod a b = narrowInt8_ (mod (toInt8_ a) (toInt8_ b))
  toInteger a = toInt8_ a

instance Read Int8 where
  readsPrec _ s = [(narrowInt8_ i, r) | (i, r) <- readsInteger_ s]

narrowInt16_ :: Integer -> Int16
narrowInt16_ x = primFixCast (primNarrow 16 1 (primFixCast x))

toInt16_ :: Int16 -> Integer
toInt16_ = primFixCast

instance Num Int16 where
  a + b = narrowInt16_ (toInt16_ a + toInt16_ b)
  a - b = narrowInt16_ (toInt16_ a - toInt16_ b)
  a * b = narrowInt16_ (toInt16_ a * toInt16_ b)
  negate a = narrowInt16_ (negate (toInt16_ a))
  abs a = narrowInt16_ (abs (toInt16_ a))
  signum a = narrowInt16_ (signum (toInt16_ a))
  fromInteger i = narrowInt16_ i

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
      else narrowInt16_ (toInteger i)
  fromEnum a = fromInteger (toInt16_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Int16}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int16}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Int16 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt16_ (-1))
               (narrowInt16_ (quot (toInt16_ a) (toInt16_ b)))
  rem a b = narrowInt16_ (rem (toInt16_ a) (toInt16_ b))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt16_ (-1))
              (narrowInt16_ (div (toInt16_ a) (toInt16_ b)))
  mod a b = narrowInt16_ (mod (toInt16_ a) (toInt16_ b))
  toInteger a = toInt16_ a

instance Read Int16 where
  readsPrec _ s = [(narrowInt16_ i, r) | (i, r) <- readsInteger_ s]

narrowInt32_ :: Integer -> Int32
narrowInt32_ x = primFixCast (primNarrow 32 1 (primFixCast x))

toInt32_ :: Int32 -> Integer
toInt32_ = primFixCast

instance Num Int32 where
  a + b = narrowInt32_ (toInt32_ a + toInt32_ b)
  a - b = narrowInt32_ (toInt32_ a - toInt32_ b)
  a * b = narrowInt32_ (toInt32_ a * toInt32_ b)
  negate a = narrowInt32_ (negate (toInt32_ a))
  abs a = narrowInt32_ (abs (toInt32_ a))
  signum a = narrowInt32_ (signum (toInt32_ a))
  fromInteger i = narrowInt32_ i

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
      else narrowInt32_ (toInteger i)
  fromEnum a = fromInteger (toInt32_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Int32}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int32}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Int32 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt32_ (-1))
               (narrowInt32_ (quot (toInt32_ a) (toInt32_ b)))
  rem a b = narrowInt32_ (rem (toInt32_ a) (toInt32_ b))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt32_ (-1))
              (narrowInt32_ (div (toInt32_ a) (toInt32_ b)))
  mod a b = narrowInt32_ (mod (toInt32_ a) (toInt32_ b))
  toInteger a = toInt32_ a

instance Read Int32 where
  readsPrec _ s = [(narrowInt32_ i, r) | (i, r) <- readsInteger_ s]

narrowInt64_ :: Integer -> Int64
narrowInt64_ x = primFixCast (primNarrow 64 1 (primFixCast x))

toInt64_ :: Int64 -> Integer
toInt64_ = primFixCast

instance Num Int64 where
  a + b = narrowInt64_ (toInt64_ a + toInt64_ b)
  a - b = narrowInt64_ (toInt64_ a - toInt64_ b)
  a * b = narrowInt64_ (toInt64_ a * toInt64_ b)
  negate a = narrowInt64_ (negate (toInt64_ a))
  abs a = narrowInt64_ (abs (toInt64_ a))
  signum a = narrowInt64_ (signum (toInt64_ a))
  fromInteger i = narrowInt64_ i

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
      else narrowInt64_ (toInteger i)
  fromEnum a = fromInteger (toInt64_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Int64}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Int64}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Int64 where
  quot a b = overflowQuot_ (a == minBound) (b == narrowInt64_ (-1))
               (narrowInt64_ (quot (toInt64_ a) (toInt64_ b)))
  rem a b = narrowInt64_ (rem (toInt64_ a) (toInt64_ b))
  div a b = overflowQuot_ (a == minBound) (b == narrowInt64_ (-1))
              (narrowInt64_ (div (toInt64_ a) (toInt64_ b)))
  mod a b = narrowInt64_ (mod (toInt64_ a) (toInt64_ b))
  toInteger a = toInt64_ a

instance Read Int64 where
  readsPrec _ s = [(narrowInt64_ i, r) | (i, r) <- readsInteger_ s]

narrowWord8_ :: Integer -> Word8
narrowWord8_ x = primFixCast (primNarrow 8 0 (primFixCast x))

toWord8_ :: Word8 -> Integer
toWord8_ = primFixCast

instance Num Word8 where
  a + b = narrowWord8_ (toWord8_ a + toWord8_ b)
  a - b = narrowWord8_ (toWord8_ a - toWord8_ b)
  a * b = narrowWord8_ (toWord8_ a * toWord8_ b)
  negate a = narrowWord8_ (negate (toWord8_ a))
  abs a = narrowWord8_ (abs (toWord8_ a))
  signum a = narrowWord8_ (signum (toWord8_ a))
  fromInteger i = narrowWord8_ i

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
      else narrowWord8_ (toInteger i)
  fromEnum a = fromInteger (toWord8_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Word8}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word8}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Word8 where
  quot a b = overflowQuot_ (False) (b == narrowWord8_ (-1))
               (narrowWord8_ (quot (toWord8_ a) (toWord8_ b)))
  rem a b = narrowWord8_ (rem (toWord8_ a) (toWord8_ b))
  div a b = overflowQuot_ (False) (b == narrowWord8_ (-1))
              (narrowWord8_ (div (toWord8_ a) (toWord8_ b)))
  mod a b = narrowWord8_ (mod (toWord8_ a) (toWord8_ b))
  toInteger a = toWord8_ a

instance Read Word8 where
  readsPrec _ s = [(narrowWord8_ i, r) | (i, r) <- readsInteger_ s]

narrowWord16_ :: Integer -> Word16
narrowWord16_ x = primFixCast (primNarrow 16 0 (primFixCast x))

toWord16_ :: Word16 -> Integer
toWord16_ = primFixCast

instance Num Word16 where
  a + b = narrowWord16_ (toWord16_ a + toWord16_ b)
  a - b = narrowWord16_ (toWord16_ a - toWord16_ b)
  a * b = narrowWord16_ (toWord16_ a * toWord16_ b)
  negate a = narrowWord16_ (negate (toWord16_ a))
  abs a = narrowWord16_ (abs (toWord16_ a))
  signum a = narrowWord16_ (signum (toWord16_ a))
  fromInteger i = narrowWord16_ i

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
      else narrowWord16_ (toInteger i)
  fromEnum a = fromInteger (toWord16_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Word16}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word16}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Word16 where
  quot a b = overflowQuot_ (False) (b == narrowWord16_ (-1))
               (narrowWord16_ (quot (toWord16_ a) (toWord16_ b)))
  rem a b = narrowWord16_ (rem (toWord16_ a) (toWord16_ b))
  div a b = overflowQuot_ (False) (b == narrowWord16_ (-1))
              (narrowWord16_ (div (toWord16_ a) (toWord16_ b)))
  mod a b = narrowWord16_ (mod (toWord16_ a) (toWord16_ b))
  toInteger a = toWord16_ a

instance Read Word16 where
  readsPrec _ s = [(narrowWord16_ i, r) | (i, r) <- readsInteger_ s]

narrowWord32_ :: Integer -> Word32
narrowWord32_ x = primFixCast (primNarrow 32 0 (primFixCast x))

toWord32_ :: Word32 -> Integer
toWord32_ = primFixCast

instance Num Word32 where
  a + b = narrowWord32_ (toWord32_ a + toWord32_ b)
  a - b = narrowWord32_ (toWord32_ a - toWord32_ b)
  a * b = narrowWord32_ (toWord32_ a * toWord32_ b)
  negate a = narrowWord32_ (negate (toWord32_ a))
  abs a = narrowWord32_ (abs (toWord32_ a))
  signum a = narrowWord32_ (signum (toWord32_ a))
  fromInteger i = narrowWord32_ i

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
      else narrowWord32_ (toInteger i)
  fromEnum a = fromInteger (toWord32_ a)
  succ a = if a == maxBound
             then error "Enum.succ{Word32}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word32}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Word32 where
  quot a b = overflowQuot_ (False) (b == narrowWord32_ (-1))
               (narrowWord32_ (quot (toWord32_ a) (toWord32_ b)))
  rem a b = narrowWord32_ (rem (toWord32_ a) (toWord32_ b))
  div a b = overflowQuot_ (False) (b == narrowWord32_ (-1))
              (narrowWord32_ (div (toWord32_ a) (toWord32_ b)))
  mod a b = narrowWord32_ (mod (toWord32_ a) (toWord32_ b))
  toInteger a = toWord32_ a

instance Read Word32 where
  readsPrec _ s = [(narrowWord32_ i, r) | (i, r) <- readsInteger_ s]

narrowWord64_ :: Integer -> Word64
narrowWord64_ x = primFixCast (primNarrow 64 0 (primFixCast x))

toWord64_ :: Word64 -> Integer
toWord64_ = primFixCast

instance Num Word64 where
  a + b = narrowWord64_ (toWord64_ a + toWord64_ b)
  a - b = narrowWord64_ (toWord64_ a - toWord64_ b)
  a * b = narrowWord64_ (toWord64_ a * toWord64_ b)
  negate a = narrowWord64_ (negate (toWord64_ a))
  abs a = narrowWord64_ (abs (toWord64_ a))
  signum a = narrowWord64_ (signum (toWord64_ a))
  fromInteger i = narrowWord64_ i

instance Bounded Word64 where
  minBound = narrowWord64_ (0)
  maxBound = narrowWord64_ (18446744073709551615)

instance Real Word64 where
  toRational a = toRational (toWord64_ a)

instance Enum Word64 where
  toEnum i =
    if i < 0
      then error ("Enum.toEnum{Word64}: tag (" ++ show i
                  ++ ") is outside of bounds (0,18446744073709551615)")
      else narrowWord64_ (toInteger i)
  fromEnum a =
    let i = toWord64_ a
    in if i > 9223372036854775807
         then errorWithoutStackTrace ("Enum.fromEnum{Word64}: value (" ++ show i
                     ++ ") is outside of Int's bounds (-9223372036854775808,9223372036854775807)")
         else fromInteger i
  succ a = if a == maxBound
             then error "Enum.succ{Word64}: tried to take `succ' of maxBound"
             else a + 1
  pred a = if a == minBound
             then error "Enum.pred{Word64}: tried to take `pred' of minBound"
             else a - 1
  enumFrom a = enumFromTo a maxBound
  enumFromTo a b = fixedEnumFromTo_ a b
  enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
  enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

instance Integral Word64 where
  quot a b = overflowQuot_ (False) (b == narrowWord64_ (-1))
               (narrowWord64_ (quot (toWord64_ a) (toWord64_ b)))
  rem a b = narrowWord64_ (rem (toWord64_ a) (toWord64_ b))
  div a b = overflowQuot_ (False) (b == narrowWord64_ (-1))
              (narrowWord64_ (div (toWord64_ a) (toWord64_ b)))
  mod a b = narrowWord64_ (mod (toWord64_ a) (toWord64_ b))
  toInteger a = toWord64_ a

instance Read Word64 where
  readsPrec _ s = [(narrowWord64_ i, r) | (i, r) <- readsInteger_ s]


-- Names GHC's Prelude exports that used to live in lib/ (M144b): the
-- zip/scan families (moved from Data.List, which re-exports them),
-- writeFile/appendFile (moved from System.IO), and the small
-- Report 9 definitions that were simply missing.

zip3 :: [a] -> [b] -> [c] -> [(a, b, c)]
zip3 (a : as) (b : bs) (c : cs) = (a, b, c) : zip3 as bs cs
zip3 _ _ _ = []

zipWith3 :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]
zipWith3 f (a : as) (b : bs) (c : cs) =
  f a b c : zipWith3 f as bs cs
zipWith3 _ _ _ _ = []

unzip3 :: [(a, b, c)] -> ([a], [b], [c])
unzip3 xs =
  ( [a | (a, _, _) <- xs]
  , [b | (_, b, _) <- xs]
  , [c | (_, _, c) <- xs]
  )

scanl :: (b -> a -> b) -> b -> [a] -> [b]
scanl f z xs =
  z : case xs of
        []      -> []
        (x : r) -> scanl f (f z x) r

scanl1 :: (a -> a -> a) -> [a] -> [a]
scanl1 _ [] = []
scanl1 f (x : xs) = scanl f x xs

scanr :: (a -> b -> b) -> b -> [a] -> [b]
scanr _ z [] = [z]
scanr f z (x : xs) = f x (head qs) : qs
  where
    qs = scanr f z xs

scanr1 :: (a -> a -> a) -> [a] -> [a]
scanr1 _ [] = []
scanr1 _ [x] = [x]
scanr1 f (x : xs) = f x (head qs) : qs
  where
    qs = scanr1 f xs


infixr 1 =<<
(=<<) :: Monad m => (a -> m b) -> m a -> m b
f =<< m = m >>= f

type ShowS = String -> String
type ReadS a = String -> [(a, String)]

showChar :: Char -> ShowS
showChar = (:)

asTypeOf :: a -> a -> a
asTypeOf = const

errorWithoutStackTrace :: String -> a
errorWithoutStackTrace s = error s

-- asinh/acosh/atanh are Floating METHODS (wired, like the rest of the
-- class); at Double/Float they are libm's. A user instance that omits
-- them gets these formulas (GHC has no default there: the instance is
-- merely incomplete) through AHC.Elaborate's built-in defaults.
-- Report 6.3.4 / 6.4 class defaults for Enum and Fractional, applied
-- to the instance's own dictionary by AHC.Elaborate's Builtin_Default
-- when a user instance omits the method (M146 review: an Enum
-- instance with only toEnum/fromEnum compiled succ and [a ..] to
-- $mMISSING - and Integral now requires Enum).
enumSuccDefault_ :: Enum a => a -> a
enumSuccDefault_ x = toEnum (fromEnum x + 1)

enumPredDefault_ :: Enum a => a -> a
enumPredDefault_ x = toEnum (fromEnum x - 1)

enumFromDefault_ :: Enum a => a -> [a]
enumFromDefault_ x = map toEnum [fromEnum x ..]

enumFromThenDefault_ :: Enum a => a -> a -> [a]
enumFromThenDefault_ x y = map toEnum [fromEnum x, fromEnum y ..]

enumFromToDefault_ :: Enum a => a -> a -> [a]
enumFromToDefault_ x y = map toEnum [fromEnum x .. fromEnum y]

enumFromThenToDefault_ :: Enum a => a -> a -> a -> [a]
enumFromThenToDefault_ x y z =
  map toEnum [fromEnum x, fromEnum y .. fromEnum z]

fracDivDefault_ :: Fractional a => a -> a -> a
fracDivDefault_ x y = x * recip y

fracRecipDefault_ :: Fractional a => a -> a
fracRecipDefault_ x = 1 / x

asinhDefault_ :: Floating a => a -> a
asinhDefault_ x = log (x + sqrt (x * x + 1.0))

acoshDefault_ :: Floating a => a -> a
acoshDefault_ x = log (x + (x + 1.0) * sqrt ((x - 1.0) / (x + 1.0)))

atanhDefault_ :: Floating a => a -> a
atanhDefault_ x = 0.5 * log ((1.0 + x) / (1.0 - x))

-- writeFile/appendFile over the handle primitives. The IOError of a
-- failed open or write is relabelled "withFile" with THIS file's name,
-- as System.IO's withFile (and GHC) report it.
writeFile :: String -> String -> IO ()
writeFile path s = withFileP_ path 1 (\i -> primHPutStr i s)

appendFile :: String -> String -> IO ()
appendFile path s = withFileP_ path 2 (\i -> primHPutStr i s)

withFileP_ :: String -> Int -> (Int -> IO a) -> IO a
withFileP_ path mode act =
  primCatch
    (primHOpen path mode >>= \i ->
       primCatch (act i >>= \r -> primHClose i >> return r)
                 (\se -> primHClose i >> primThrowIO se))
    (\se ->
       if primExcKind se == 3
         then let e = primExcIO se
              in primThrowIO (primExcFromIO
                   (primMkIOError (primIoeType e) "withFile"
                                  (primIoeDescription e) (Just path)))
         else primThrowIO se)
