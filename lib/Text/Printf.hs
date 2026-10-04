module Text.Printf
  ( printf, hPrintf, PrintfType, HPrintfType, PrintfArg (..)
  , UPrintf (..), IsChar (..)
  ) where

-- Text.Printf (M142), in base's shape: printf's result type picks the
-- instance - String, IO a, or a function taking one more argument -
-- which needs instances over (->) (the M142 typechecker change). The
-- formatting logic follows base-4.17's Text.Printf: field adjustment,
-- sign flags, `#` prefixes, `*` widths, unsigned views of negatives,
-- and %f/%e/%g through Numeric's shortest-digit formatters (so `%f`
-- with no precision prints 3.14159, not C's 3.141590).

import System.IO (Handle, hPutStr)
import Numeric (showEFloat, showFFloat, showGFloat, showFFloatAlt,
                showGFloatAlt)
import Data.Char (intToDigit, toUpper, toLower, isUpper, isDigit, chr, ord)
import Data.Int
import Data.Word

-- | A formatted argument. Integers carry their type's minBound when it
-- has one (Nothing for Integer): %u/%x/%o/%b view a negative value as
-- unsigned at that width, as base does.
data UPrintf = UInteger Integer (Maybe Integer)
             | UChar Char
             | UString String
             | UDouble Double
             | UFloat Float      -- its own shortest digits, not Double's

class PrintfArg a where
  toUPrintf :: a -> UPrintf

instance PrintfArg Int     where toUPrintf x = UInteger (toInteger x) (Just (toInteger (minBound :: Int)))
instance PrintfArg Integer where toUPrintf x = UInteger x Nothing
instance PrintfArg Int8    where toUPrintf x = UInteger (toInteger x) (Just (toInteger (minBound :: Int8)))
instance PrintfArg Int16   where toUPrintf x = UInteger (toInteger x) (Just (toInteger (minBound :: Int16)))
instance PrintfArg Int32   where toUPrintf x = UInteger (toInteger x) (Just (toInteger (minBound :: Int32)))
instance PrintfArg Int64   where toUPrintf x = UInteger (toInteger x) (Just (toInteger (minBound :: Int64)))
instance PrintfArg Word8   where toUPrintf x = UInteger (toInteger x) (Just 0)
instance PrintfArg Word16  where toUPrintf x = UInteger (toInteger x) (Just 0)
instance PrintfArg Word32  where toUPrintf x = UInteger (toInteger x) (Just 0)
instance PrintfArg Word64  where toUPrintf x = UInteger (toInteger x) (Just 0)
instance PrintfArg Double  where toUPrintf = UDouble
instance PrintfArg Float   where toUPrintf = UFloat
instance PrintfArg Char    where toUPrintf = UChar
instance IsChar c => PrintfArg [c] where
  toUPrintf = UString . map toChar

class IsChar c where
  toChar   :: c -> Char
  fromChar :: Char -> c

instance IsChar Char where
  toChar c = c
  fromChar c = c

class PrintfType r where
  spr :: String -> [UPrintf] -> r

instance IsChar c => PrintfType [c] where
  spr fmts args = map fromChar (uprintf fmts (reverse args))

instance PrintfType (IO a) where
  spr fmts args = putStr (uprintf fmts (reverse args)) >> return undefined

instance (PrintfArg a, PrintfType r) => PrintfType (a -> r) where
  spr fmts args = \a -> spr fmts (toUPrintf a : args)

printf :: PrintfType r => String -> r
printf fmts = spr fmts []

class HPrintfType r where
  hspr :: Handle -> String -> [UPrintf] -> r

instance HPrintfType (IO a) where
  hspr h fmts args = hPutStr h (uprintf fmts (reverse args)) >> return undefined

instance (PrintfArg a, HPrintfType r) => HPrintfType (a -> r) where
  hspr h fmts args = \a -> hspr h fmts (toUPrintf a : args)

hPrintf :: HPrintfType r => Handle -> String -> r
hPrintf h fmts = hspr h fmts []

------------------------------------------------------------------
-- The format interpreter (base's uprintfs / getSpecs / formatters)
------------------------------------------------------------------

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

data Adjust = LeftAdjust | ZeroPad
data Sign = SignPlus | SignSpace

data Spec = Spec
  { sAdjust :: Maybe Adjust
  , sSign   :: Maybe Sign
  , sAlt    :: Bool
  , sWidth  :: Maybe Int
  , sPrec   :: Maybe Int
  , sChar   :: Char
  }

uprintf :: String -> [UPrintf] -> String
uprintf "" []                = ""
uprintf "" (_ : _)           = errorShortFormat
uprintf ('%' : '%' : cs) us  = '%' : uprintf cs us
uprintf ('%' : _) []         = errorMissingArgument
uprintf ('%' : cs) us        =
  let (spec, cs', us') = getSpecs cs us
  in case us' of
       []         -> errorMissingArgument
       (u : rest) -> formatArg spec u ++ uprintf cs' rest
uprintf (c : cs) us          = c : uprintf cs us

-- Flags, width, precision, length modifiers, conversion character.
getSpecs :: String -> [UPrintf] -> (Spec, String, [UPrintf])
getSpecs = flags (Spec Nothing Nothing False Nothing Nothing 'v')
  where
    flags sp ('-' : cs) us = flags sp { sAdjust = Just LeftAdjust } cs us
    flags sp ('0' : cs) us = flags sp { sAdjust = zeroPad (sAdjust sp) } cs us
    flags sp ('+' : cs) us = flags sp { sSign = Just SignPlus } cs us
    flags sp (' ' : cs) us = flags sp { sSign = spaceSign (sSign sp) } cs us
    flags sp ('#' : cs) us = flags sp { sAlt = True } cs us
    flags sp cs us = width sp cs us

    width sp ('*' : cs) us = case us of
      (UInteger n _ : us') ->
        let w = fromInteger n
            sp' = if w < 0 then sp { sAdjust = Just LeftAdjust, sWidth = Just (negate w) }
                           else sp { sWidth = Just w }
        in prec sp' cs us'
      (_ : _) -> errorBadArgument
      []      -> errorMissingArgument
    width sp cs us = case span isDigit cs of
      ("", _)     -> prec sp cs us
      (ds, rest)  -> prec sp { sWidth = Just (read ds) } rest us

    prec sp ('.' : '*' : cs) us = case us of
      (UInteger n _ : us') -> modifiers sp { sPrec = Just (fromInteger n) } cs us'
      (_ : _) -> errorBadArgument
      []      -> errorMissingArgument
    prec sp ('.' : cs) us = case span isDigit cs of
      (ds, rest) -> modifiers sp { sPrec = Just (if null ds then 0 else read ds) } rest us
    prec sp cs us = modifiers sp cs us

    modifiers sp ('h' : 'h' : cs) us = conv sp cs us
    modifiers sp ('h' : cs) us       = conv sp cs us
    modifiers sp ('l' : 'l' : cs) us = conv sp cs us
    modifiers sp ('l' : cs) us       = conv sp cs us
    modifiers sp ('L' : cs) us       = conv sp cs us
    modifiers sp cs us               = conv sp cs us

    conv _ "" _ = errorShortFormat
    conv sp (c : cs) us = (sp { sChar = c }, cs, us)

    -- '-' wins over '0', '+' over ' ' - in either order, as base.
    zeroPad (Just LeftAdjust) = Just LeftAdjust
    zeroPad _                 = Just ZeroPad
    spaceSign (Just SignPlus) = Just SignPlus
    spaceSign _               = Just SignSpace

formatArg :: Spec -> UPrintf -> String
formatArg sp u = case u of
  UInteger i m -> formatInteger sp i m
  UChar c      -> formatChar sp c
  UString s    -> formatString sp s
  UDouble d    -> formatDouble sp d
  UFloat f     -> formatDouble sp f

formatChar :: Spec -> Char -> String
formatChar sp c = case sChar sp of
  'c' -> adjust sp ("", [c])
  'v' -> adjust sp ("", [c])
  ch  -> errorBadFormat ch

formatString :: Spec -> String -> String
formatString sp s = case sChar sp of
  's' -> adjust sp ("", trunc (sPrec sp) s)
  'v' -> adjust sp ("", trunc (sPrec sp) s)
  ch  -> errorBadFormat ch
  where
    trunc Nothing str  = str
    trunc (Just n) str = take n str

formatInteger :: Spec -> Integer -> Maybe Integer -> String
formatInteger sp i m = case sChar sp of
  'd' -> adjustSigned sp (fmti (sPrec sp) i)
  'i' -> adjustSigned sp (fmti (sPrec sp) i)
  'v' -> adjustSigned sp (fmti (sPrec sp) i)
  'x' -> adjust sp (fmtu 16 (alt "0x") (sPrec sp) m i)
  'X' -> adjust sp (upcase (fmtu 16 (alt "0X") (sPrec sp) m i))
  'b' -> adjust sp (fmtu 2 (alt "0b") (sPrec sp) m i)
  'o' -> adjust sp (fmtu 8 (alt "0") (sPrec sp) m i)
  'u' -> adjust sp (fmtu 10 Nothing (sPrec sp) m i)
  'c' | i >= toInteger (ord (minBound :: Char))
        && i <= toInteger (ord (maxBound :: Char))
        && sPrec sp == Nothing
      -> formatChar sp { sChar = 'c' } (chr (fromInteger i))
  ch  -> errorBadFormat ch
  where
    alt p = if sAlt sp then Just p else Nothing
    upcase (s1, s2) = (s1, map toUpper s2)

fmti :: Maybe Int -> Integer -> (String, String)
fmti p i
  | i < 0     = ("-", integralPrec p (show (negate i)))
  | otherwise = ("", integralPrec p (show i))

fmtu :: Integer -> Maybe String -> Maybe Int -> Maybe Integer -> Integer
     -> (String, String)
fmtu b (Just pre) p m i =
  let ("", s) = fmtu b Nothing p m i in
  case pre of
    "0" -> case s of
             '0' : _ -> ("", s)
             _       -> (pre, s)
    _   -> (pre, s)
fmtu b Nothing p0 m0 i0 = case fmtu' p0 m0 i0 of
  Just s  -> ("", s)
  Nothing -> errorBadArgument
  where
    fmtu' prec (Just m) i | i < 0 = fmtu' prec Nothing (-2 * m + i)
    fmtu' (Just prec) _ i | i >= 0 = fmap (integralPrec (Just prec)) (fmtu' Nothing Nothing i)
    fmtu' Nothing _ i | i >= 0 = Just (showIntegerAtBase b i)
    fmtu' _ _ _ = Nothing

showIntegerAtBase :: Integer -> Integer -> String
showIntegerAtBase b n
  | n < b     = [intToDigit (fromInteger n)]
  | otherwise = showIntegerAtBase b (n `div` b) ++ [intToDigit (fromInteger (n `mod` b))]

integralPrec :: Maybe Int -> String -> String
integralPrec Nothing s = s
integralPrec (Just 0) "0" = ""
integralPrec (Just p) s = replicate (p - length s) '0' ++ s

formatDouble :: (RealFloat a, Show a) => Spec -> a -> String
formatDouble sp d = case sChar sp of
  c | c `elem` "eEfFgG" -> adjustSigned sp (dfmt c (sPrec sp) (sAlt sp) d)
  'v'                    -> adjustSigned sp (dfmt 'g' (sPrec sp) (sAlt sp) d)
  ch                     -> errorBadFormat ch

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

adjust :: Spec -> (String, String) -> String
adjust sp (pre, str) =
  let naturalWidth = length pre + length str
      zero = case sAdjust sp of { Just ZeroPad -> True; _ -> False }
      left = case sAdjust sp of { Just LeftAdjust -> True; _ -> False }
      fill = case sWidth sp of
        Just width | naturalWidth < width ->
          Just (replicate (width - naturalWidth) (if zero then '0' else ' '))
        _ -> Nothing
  in case fill of
       Just f | left      -> pre ++ str ++ f
              | zero      -> pre ++ f ++ str
              | otherwise -> f ++ pre ++ str
       Nothing -> pre ++ str

adjustSigned :: Spec -> (String, String) -> String
adjustSigned sp ("", str) = case sSign sp of
  Just SignPlus  -> adjust sp ("+", str)
  Just SignSpace -> adjust sp (" ", str)
  Nothing        -> adjust sp ("", str)
adjustSigned sp ps = adjust sp ps
