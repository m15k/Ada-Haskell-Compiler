module Text.Printf
  ( printf, hPrintf, PrintfType, HPrintfType
  , PrintfArg (..), FieldFormatter, FieldFormat (..)
  , FormatAdjustment (..), FormatSign (..), vFmt
  , ModifierParser, FormatParse (..)
  , formatString, formatChar, formatInt, formatInteger, formatRealFloat
  , errorBadFormat, errorShortFormat, errorMissingArgument
  , errorBadArgument, perror
  , IsChar (..)
  ) where

-- Text.Printf (M142), transcribed from base-4.17's Text.Printf: each
-- argument contributes a modifier parser and a field formatter
-- (base's UPrintf pair), so length modifiers, `*` arguments and the
-- Char-as-integer conversions behave exactly as base's - `%d` of a
-- Char is its code point, `%hhx` narrows to 8 bits, `%ls` is a bad
-- formatting char 'l', and a `*` argument is formatted with 'd'.
-- printf's result type picks the instance - String, IO a, or a
-- function taking one more argument (instances over (->)).
--
-- One signature difference from base: formatRealFloat is
-- (RealFloat a, Show a) => (Numeric's shortest digits come from show).
-- And base's IO instance is `(a ~ ()) => PrintfType (IO a)`, which
-- Haskell 2010 cannot state; the action's result here is a value
-- nothing inspects (main's result is never forced, as in GHC).

import System.IO (Handle, hPutStr)
import Numeric (showEFloat, showFFloat, showGFloat, showFFloatAlt,
                showGFloatAlt)
import Data.Char (intToDigit, toUpper, toLower, isUpper, isDigit, chr, ord)
import Data.Int
import Data.Word

-------------------------------------------------------------------
-- The classes
-------------------------------------------------------------------

class PrintfType r where
  spr :: String -> [UPrintf] -> r

class HPrintfType r where
  hspr :: Handle -> String -> [UPrintf] -> r

instance IsChar c => PrintfType [c] where
  spr fmts args = map fromChar (uprintf fmts (reverse args))

instance PrintfType (IO a) where
  spr fmts args =
    putStr (uprintf fmts (reverse args)) >> return (perror "the result of an IO printf")

instance HPrintfType (IO a) where
  hspr hdl fmts args =
    hPutStr hdl (uprintf fmts (reverse args)) >> return (perror "the result of an IO hPrintf")

instance (PrintfArg a, PrintfType r) => PrintfType (a -> r) where
  spr fmts args = \a -> spr fmts ((parseFormat a, formatArg a) : args)

instance (PrintfArg a, HPrintfType r) => HPrintfType (a -> r) where
  hspr hdl fmts args = \a -> hspr hdl fmts ((parseFormat a, formatArg a) : args)

printf :: PrintfType r => String -> r
printf fmts = spr fmts []

hPrintf :: HPrintfType r => Handle -> String -> r
hPrintf hdl fmts = hspr hdl fmts []

class PrintfArg a where
  formatArg :: a -> FieldFormatter
  parseFormat :: a -> ModifierParser
  parseFormat _ (c : cs) = FormatParse "" c cs
  parseFormat _ ""       = errorShortFormat

instance PrintfArg Char where
  formatArg = formatChar
  parseFormat _ cf = parseIntFormat cf

instance IsChar c => PrintfArg [c] where
  formatArg = formatString

instance PrintfArg Int where
  formatArg x = formatIntB (toInteger x) (-9223372036854775808)
  parseFormat _ = parseIntFormat
instance PrintfArg Int8 where
  formatArg x = formatIntB (toInteger x) (-128)
  parseFormat _ = parseIntFormat
instance PrintfArg Int16 where
  formatArg x = formatIntB (toInteger x) (-32768)
  parseFormat _ = parseIntFormat
instance PrintfArg Int32 where
  formatArg x = formatIntB (toInteger x) (-2147483648)
  parseFormat _ = parseIntFormat
instance PrintfArg Int64 where
  formatArg x = formatIntB (toInteger x) (-9223372036854775808)
  parseFormat _ = parseIntFormat
instance PrintfArg Word8 where
  formatArg x = formatIntB (toInteger x) 0
  parseFormat _ = parseIntFormat
instance PrintfArg Word16 where
  formatArg x = formatIntB (toInteger x) 0
  parseFormat _ = parseIntFormat
instance PrintfArg Word32 where
  formatArg x = formatIntB (toInteger x) 0
  parseFormat _ = parseIntFormat
instance PrintfArg Word64 where
  formatArg x = formatIntB (toInteger x) 0
  parseFormat _ = parseIntFormat
instance PrintfArg Integer where
  formatArg = formatInteger
  parseFormat _ = parseIntFormat
instance PrintfArg Float where
  formatArg = formatRealFloat
instance PrintfArg Double where
  formatArg = formatRealFloat

class IsChar c where
  toChar   :: c -> Char
  fromChar :: Char -> c

instance IsChar Char where
  toChar c = c
  fromChar c = c

-------------------------------------------------------------------
-- Field formats
-------------------------------------------------------------------

data FormatAdjustment = LeftAdjust | ZeroPad

data FormatSign = SignPlus | SignSpace

data FieldFormat = FieldFormat
  { fmtWidth     :: Maybe Int
  , fmtPrecision :: Maybe Int
  , fmtAdjust    :: Maybe FormatAdjustment
  , fmtSign      :: Maybe FormatSign
  , fmtAlternate :: Bool
  , fmtModifiers :: String
  , fmtChar      :: Char
  }

data FormatParse = FormatParse
  { fpModifiers :: String
  , fpChar      :: Char
  , fpRest      :: String
  }

type FieldFormatter = FieldFormat -> ShowS

type ModifierParser = String -> FormatParse

-- base's UPrintf: how to parse this argument's modifiers, and how to
-- format it.
type UPrintf = (ModifierParser, FieldFormatter)

-- The length modifiers and the minBound each one narrows to.
intModifierMap :: [(String, Integer)]
intModifierMap =
  [ ("hh", -128)
  , ("h",  -32768)
  , ("l",  -2147483648)
  , ("ll", -9223372036854775808)
  , ("L",  -9223372036854775808) ]

-- The longest modifier prefix wins (base's foldr over the map).
parseIntFormat :: String -> FormatParse
parseIntFormat s =
  case foldr matchPrefix Nothing intModifierMap of
    Just m  -> m
    Nothing -> case s of
      c : cs -> FormatParse "" c cs
      ""     -> errorShortFormat
  where
    matchPrefix (p, _) m = case m of
      Just (FormatParse p0 _ _)
        | length p0 >= length p -> m
        | otherwise -> case getFormat p of
            Nothing -> m
            Just fp -> Just fp
      Nothing -> getFormat p
    getFormat p = case stripPre p s of
      Nothing -> Nothing
      Just (c : cs) -> Just (FormatParse p c cs)
      Just "" -> errorShortFormat
    stripPre [] ys = Just ys
    stripPre (x : xs) (y : ys) | x == y = stripPre xs ys
    stripPre _ _ = Nothing

vFmt :: Char -> FieldFormat -> FieldFormat
vFmt c ufmt = case fmtChar ufmt of
  'v' -> ufmt { fmtChar = c }
  _   -> ufmt

formatChar :: Char -> FieldFormatter
formatChar x ufmt = formatIntegral (Just 0) (toInteger (ord x)) (vFmt 'c' ufmt)

formatString :: IsChar c => [c] -> FieldFormatter
formatString x ufmt =
  case fmtChar (vFmt 's' ufmt) of
    's' -> \rest -> adjust ufmt ("", ts) ++ rest
    c   -> errorBadFormat c
  where
    ts = map toChar (trunc (fmtPrecision ufmt))
    trunc Nothing  = x
    trunc (Just n) = take n x

fixupMods :: FieldFormat -> Maybe Integer -> Maybe Integer
fixupMods ufmt m =
  case fmtModifiers ufmt of
    ""   -> m
    mods -> case lookup mods intModifierMap of
      Just m0 -> Just m0
      Nothing -> perror "unknown format modifier"

-- base's formatInt, with the type's minBound passed in (Haskell 2010
-- has no scoped type variables to name it).
formatIntB :: Integer -> Integer -> FieldFormatter
formatIntB x lb ufmt =
  let m = fixupMods ufmt (Just lb)
      ufmt' = if lb == 0 then vFmt 'u' ufmt else ufmt
  in formatIntegral m x ufmt'

formatInt :: (Integral a, Bounded a) => a -> FieldFormatter
formatInt x = formatIntB (toInteger x) (toInteger (minBound `sameType` x))

sameType :: a -> a -> a
sameType a _ = a

formatInteger :: Integer -> FieldFormatter
formatInteger x ufmt = formatIntegral (fixupMods ufmt Nothing) x ufmt

formatIntegral :: Maybe Integer -> Integer -> FieldFormatter
formatIntegral m x ufmt0 =
  let prec = fmtPrecision ufmt0 in
  case fmtChar ufmt of
    'd' -> (adjustSigned ufmt (fmti prec x) ++)
    'i' -> (adjustSigned ufmt (fmti prec x) ++)
    'x' -> (adjust ufmt (fmtu 16 (alt "0x" x) prec m x) ++)
    'X' -> (adjust ufmt (upcase (fmtu 16 (alt "0X" x) prec m x)) ++)
    'b' -> (adjust ufmt (fmtu 2 (alt "0b" x) prec m x) ++)
    'o' -> (adjust ufmt (fmtu 8 (alt "0" x) prec m x) ++)
    'u' -> (adjust ufmt (fmtu 10 Nothing prec m x) ++)
    'c' | x >= 0 && x <= 1114111
          && isNothing (fmtPrecision ufmt)
          && null (fmtModifiers ufmt) ->
            formatString [chr (fromInteger x)] (ufmt { fmtChar = 's' })
    'c' -> perror "illegal char conversion"
    c   -> errorBadFormat c
  where
    -- a precision overrides the 0 flag, as C's printf
    ufmt = vFmt 'd' (case (fmtPrecision ufmt0, fmtAdjust ufmt0) of
                       (Just _, Just ZeroPad) -> ufmt0 { fmtAdjust = Nothing }
                       _ -> ufmt0)
    alt _ 0 = Nothing
    alt p _ = if fmtAlternate ufmt then Just p else Nothing
    upcase (s1, s2) = (s1, map toUpper s2)
    isNothing Nothing = True
    isNothing _ = False

formatRealFloat :: (RealFloat a, Show a) => a -> FieldFormatter
formatRealFloat x ufmt =
  let c = fmtChar (vFmt 'g' ufmt)
      prec = fmtPrecision ufmt
      alt = fmtAlternate ufmt
  in if c `elem` "eEfFgG"
       then (adjustSigned ufmt (dfmt c prec alt x) ++)
       else errorBadFormat c

-------------------------------------------------------------------
-- The interpreter (base's uprintfs / getSpecs)
-------------------------------------------------------------------

uprintf :: String -> [UPrintf] -> String
uprintf s us = uprintfs s us ""

uprintfs :: String -> [UPrintf] -> ShowS
uprintfs ""             []      = id
uprintfs ""             (_ : _) = errorShortFormat
uprintfs ('%' : '%' : cs) us    = ('%' :) . uprintfs cs us
uprintfs ('%' : _)      []      = errorMissingArgument
uprintfs ('%' : cs)     us      = fmt cs us
uprintfs (c : cs)       us      = (c :) . uprintfs cs us

fmt :: String -> [UPrintf] -> ShowS
fmt cs0 us0 =
  case getSpecs False False Nothing False cs0 us0 of
    (_, _, [])                  -> errorMissingArgument
    (ufmt, cs, (_, u) : us)     -> u ufmt . uprintfs cs us

adjust :: FieldFormat -> (String, String) -> String
adjust ufmt (pre, str) =
  let naturalWidth = length pre + length str
      zero = case fmtAdjust ufmt of { Just ZeroPad -> True; _ -> False }
      left = case fmtAdjust ufmt of { Just LeftAdjust -> True; _ -> False }
      fill = case fmtWidth ufmt of
        Just width | naturalWidth < width ->
          replicate (width - naturalWidth) (if zero then '0' else ' ')
        _ -> ""
  in if left then pre ++ str ++ fill
     else if zero then pre ++ fill ++ str
     else fill ++ pre ++ str

adjustSigned :: FieldFormat -> (String, String) -> String
adjustSigned ufmt ("", str) = case fmtSign ufmt of
  Just SignPlus  -> adjust ufmt ("+", str)
  Just SignSpace -> adjust ufmt (" ", str)
  Nothing        -> adjust ufmt ("", str)
adjustSigned ufmt ps = adjust ufmt ps

fmti :: Maybe Int -> Integer -> (String, String)
fmti prec i
  | i < 0     = ("-", integralPrec prec (show (negate i)))
  | otherwise = ("", integralPrec prec (show i))

fmtu :: Integer -> Maybe String -> Maybe Int -> Maybe Integer -> Integer
     -> (String, String)
fmtu b (Just pre) prec m i =
  let s = snd (fmtu b Nothing prec m i) in
  case pre of
    "0" -> case s of
             '0' : _ -> ("", s)
             _       -> (pre, s)
    _   -> (pre, s)
fmtu b Nothing prec0 m0 i0 = case fmtu' prec0 m0 i0 of
  Just s  -> ("", s)
  Nothing -> errorBadArgument
  where
    fmtu' prec (Just m) i | i < 0 = fmtu' prec Nothing (-2 * m + i)
    fmtu' (Just prec) _ i | i >= 0 =
      fmap (integralPrec (Just prec)) (fmtu' Nothing Nothing i)
    fmtu' Nothing _ i | i >= 0 = Just (showIntegerAtBase b i)
    fmtu' _ _ _ = Nothing

showIntegerAtBase :: Integer -> Integer -> String
showIntegerAtBase b n0 = go n0 ""
  where
    go n acc
      | n < b     = intToDigit (fromInteger n) : acc
      | otherwise = go (n `div` b) (intToDigit (fromInteger (n `mod` b)) : acc)

integralPrec :: Maybe Int -> String -> String
integralPrec Nothing s = s
integralPrec (Just 0) "0" = ""
integralPrec (Just p) s = replicate (p - length s) '0' ++ s

stoi :: String -> (Int, String)
stoi cs = case span isDigit cs of
  ("", cs') -> (0, cs')
  (as, cs') -> (read as, cs')

adjustment :: Maybe Int -> Maybe a -> Bool -> Bool -> Maybe FormatAdjustment
adjustment w p l z = case w of
  Just n | n < 0 -> adjl p True z
  _              -> adjl p l z
  where
    adjl _ True _      = Just LeftAdjust
    adjl _ False True  = Just ZeroPad
    adjl _ _ _         = Nothing

mkFormat :: Maybe Int -> Maybe Int -> Bool -> Bool -> Maybe FormatSign
         -> Bool -> FormatParse -> FieldFormat
mkFormat w p l z s a (FormatParse ms c _) = FieldFormat
  { fmtWidth = fmap abs w
  , fmtPrecision = p
  , fmtAdjust = adjustment w p l z
  , fmtSign = s
  , fmtAlternate = a
  , fmtModifiers = ms
  , fmtChar = c }

-- The next argument's own modifier parser reads the conversion.
parseWith :: [UPrintf] -> String -> FormatParse
parseWith us cs = case us of
  (ufmt, _) : _ -> ufmt cs
  []            -> errorMissingArgument

getSpecs :: Bool -> Bool -> Maybe FormatSign -> Bool -> String -> [UPrintf]
         -> (FieldFormat, String, [UPrintf])
getSpecs _ z s a ('-' : cs0) us = getSpecs True z s a cs0 us
getSpecs l z _ a ('+' : cs0) us = getSpecs l z (Just SignPlus) a cs0 us
getSpecs l z s a (' ' : cs0) us = getSpecs l z ss a cs0 us
  where ss = case s of
               Just SignPlus -> Just SignPlus
               _             -> Just SignSpace
getSpecs l _ s a ('0' : cs0) us = getSpecs l True s a cs0 us
getSpecs l z s _ ('#' : cs0) us = getSpecs l z s True cs0 us
getSpecs l z s a ('*' : cs0) us =
  let (us', n) = getStar us
      ((p, cs''), us'') = case cs0 of
        '.' : '*' : r -> let (us''', p') = getStar us' in ((Just p', r), us''')
        '.' : r       -> let (p', r') = stoi r in ((Just p', r'), us')
        _             -> ((Nothing, cs0), us')
      fp = parseWith us'' cs''
  in (mkFormat (Just n) p l z s a fp, fpRest fp, us'')
getSpecs l z s a ('.' : cs0) us =
  let ((p, cs'), us') = case cs0 of
        '*' : cs'' -> let (us'', p') = getStar us in ((p', cs''), us'')
        _          -> (stoi cs0, us)
      fp = parseWith us' cs'
  in (mkFormat Nothing (Just p) l z s a fp, fpRest fp, us')
getSpecs l z s a cs0@(c0 : _) us | isDigit c0 =
  let (n, cs') = stoi cs0
      ((p, cs''), us') = case cs' of
        '.' : '*' : r -> let (us'', p') = getStar us in ((Just p', r), us'')
        '.' : r       -> let (p', r') = stoi r in ((Just p', r'), us)
        _             -> ((Nothing, cs'), us)
      fp = parseWith us' cs''
  in (mkFormat (Just n) p l z s a fp, fpRest fp, us')
getSpecs l z s a cs0@(_ : _) us =
  let fp = parseWith us cs0
  in (mkFormat Nothing Nothing l z s a fp, fpRest fp, us)
getSpecs _ _ _ _ "" _ = errorShortFormat

-- A `*` argument is formatted with %d and read back, as base: a Char
-- gives its code point, a Double or String is a bad formatting char.
getStar :: [UPrintf] -> ([UPrintf], Int)
getStar us =
  let ufmt = FieldFormat Nothing Nothing Nothing Nothing False "" 'd' in
  case us of
    []            -> errorMissingArgument
    (_, nu) : us' -> (us', read (nu ufmt ""))

dfmt :: (RealFloat a, Show a) => Char -> Maybe Int -> Bool -> a -> (String, String)
dfmt c p a d =
  let caseConvert = if isUpper c then map toUpper else id
      showFunction = case toLower c of
        'e' -> showEFloat
        'f' -> if a then showFFloatAlt else showFFloat
        'g' -> if a then showGFloatAlt else showGFloat
        _   -> perror "internal error: impossible dfmt"
      result = caseConvert (showFunction p d "")
  in case result of
       '-' : cs -> ("-", cs)
       cs       -> ("", cs)

-------------------------------------------------------------------
-- Errors, exactly base's texts
-------------------------------------------------------------------

perror :: String -> a
perror s = error ("printf: " ++ s)

errorBadFormat :: Char -> a
errorBadFormat c = perror ("bad formatting char " ++ show c)

errorShortFormat :: a
errorShortFormat = perror "formatting string ended prematurely"

errorMissingArgument :: a
errorMissingArgument = perror "argument list ended prematurely"

errorBadArgument :: a
errorBadArgument = perror "bad argument"
