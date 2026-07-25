-- ajson - a JSON parser and pretty-printer, the second dogfood
-- program (the first was examples/lisp). Written in the Haskell
-- subset AHC compiles, and REQUIRED to behave byte-identically
-- compiled by AHC or interpreted by GHC - the goldens are GHC's
-- output, per house rules.
--
--   ajson FILE.json           parse and pretty-print (2-space)
--   ajson --stats FILE.json   object-key frequency table (Data.Map)
--   ajson                     read stdin, pretty-print
--
-- Design notes, all in service of determinism across compilers:
-- * Numbers are built by fromRational of the EXACT decimal ratio
--   (mantissa % 10^k), so the Double is the correctly rounded
--   value of the literal on both compilers - the same machinery
--   AHC uses for float literals since v1.4.
-- * Strings store \uXXXX escapes as real code points internally,
--   and the renderer re-escapes anything outside printable ASCII,
--   so program IO stays ASCII end to end.
-- * Errors are reported on stdout with a byte offset and the
--   program exits normally - keeps the goldens one-channel.

import Data.Char (chr, ord, isDigit, digitToInt, intToDigit)
import System.Environment (getArgs)
import Data.List (intercalate, sortBy)
import Data.Ratio ((%))
import qualified Data.Map as Map

data JValue
  = JNull
  | JBool Bool
  | JNum Double
  | JStr String
  | JArr [JValue]
  | JObj [(String, JValue)]

--  A parse either succeeds with a value and the rest of the input
--  (plus the byte offset reached), or fails at an offset.
data Res a = Good a String Int | Bad Int String

------------------------------------------------------------------
--  Lexical layer
------------------------------------------------------------------

skipWS :: String -> Int -> (String, Int)
skipWS (c : cs) n
  | c == ' ' || c == '\t' || c == '\n' || c == '\r' =
      skipWS cs (n + 1)
skipWS s n = (s, n)

want :: String -> String -> Int -> Res ()
want lit s n = go lit s n
  where go :: String -> String -> Int -> Res ()
        go [] rest m = Good () rest m
        go (l : ls) (c : cs) m
          | l == c = go ls cs (m + 1)
        go _ _ m = Bad m ("expected '" ++ lit ++ "'")

------------------------------------------------------------------
--  Values
------------------------------------------------------------------

pValue :: String -> Int -> Res JValue
pValue s0 n0 =
  case skipWS s0 n0 of
    ([], n) -> Bad n "expected a value"
    (s@(c : cs), n)
      | c == '{' -> pObject cs (n + 1)
      | c == '[' -> pArray cs (n + 1)
      | c == '"' -> case pString cs (n + 1) of
          Good str rest m -> Good (JStr str) rest m
          Bad m e -> Bad m e
      | c == 't' -> case want "true" s n of
          Good _ rest m -> Good (JBool True) rest m
          Bad m e -> Bad m e
      | c == 'f' -> case want "false" s n of
          Good _ rest m -> Good (JBool False) rest m
          Bad m e -> Bad m e
      | c == 'n' -> case want "null" s n of
          Good _ rest m -> Good JNull rest m
          Bad m e -> Bad m e
      | c == '-' || isDigit c -> pNumber s n
      | otherwise -> Bad n ("unexpected '" ++ [c] ++ "'")

pObject :: String -> Int -> Res JValue
pObject s0 n0 =
  case skipWS s0 n0 of
    ('}' : cs, n) -> Good (JObj []) cs (n + 1)
    (s, n) -> pMembers s n []
  where
    pMembers :: String -> Int -> [(String, JValue)] -> Res JValue
    pMembers s n acc =
      case skipWS s n of
        ('"' : cs, m) ->
          case pString cs (m + 1) of
            Bad m2 e -> Bad m2 e
            Good key rest m2 ->
              case skipWS rest m2 of
                (':' : cs2, m3) ->
                  case pValue cs2 (m3 + 1) of
                    Bad m4 e -> Bad m4 e
                    Good v rest2 m4 ->
                      case skipWS rest2 m4 of
                        (',' : cs3, m5) ->
                          pMembers cs3 (m5 + 1)
                                   ((key, v) : acc)
                        ('}' : cs3, m5) ->
                          Good (JObj (reverse ((key, v) : acc)))
                               cs3 (m5 + 1)
                        (_, m5) ->
                          Bad m5 "expected ',' or '}'"
                (_, m3) -> Bad m3 "expected ':'"
        (_, m) -> Bad m "expected a key string"

pArray :: String -> Int -> Res JValue
pArray s0 n0 =
  case skipWS s0 n0 of
    (']' : cs, n) -> Good (JArr []) cs (n + 1)
    (s, n) -> pItems s n []
  where
    pItems :: String -> Int -> [JValue] -> Res JValue
    pItems s n acc =
      case pValue s n of
        Bad m e -> Bad m e
        Good v rest m ->
          case skipWS rest m of
            (',' : cs, m2) -> pItems cs (m2 + 1) (v : acc)
            (']' : cs, m2) ->
              Good (JArr (reverse (v : acc))) cs (m2 + 1)
            (_, m2) -> Bad m2 "expected ',' or ']'"

------------------------------------------------------------------
--  Strings (input cursor is just past the opening quote)
------------------------------------------------------------------

pString :: String -> Int -> Res String
pString s0 n0 = go s0 n0 []
  where
    go :: String -> Int -> [Char] -> Res String
    go [] n _ = Bad n "unterminated string"
    go ('"' : cs) n acc = Good (reverse acc) cs (n + 1)
    go ('\\' : cs) n acc = esc cs (n + 1) acc
    go (c : cs) n acc
      | ord c < 32 = Bad n "raw control character in string"
      | otherwise = go cs (n + 1) (c : acc)

    esc :: String -> Int -> [Char] -> Res String
    esc [] n _ = Bad n "unterminated escape"
    esc (e : cs) n acc
      | e == '"' = go cs (n + 1) ('"' : acc)
      | e == '\\' = go cs (n + 1) ('\\' : acc)
      | e == '/' = go cs (n + 1) ('/' : acc)
      | e == 'b' = go cs (n + 1) (chr 8 : acc)
      | e == 'f' = go cs (n + 1) (chr 12 : acc)
      | e == 'n' = go cs (n + 1) ('\n' : acc)
      | e == 'r' = go cs (n + 1) ('\r' : acc)
      | e == 't' = go cs (n + 1) ('\t' : acc)
      | e == 'u' = hex4 cs (n + 1) acc
      | otherwise = Bad n ("bad escape '\\" ++ [e] ++ "'")

    hex4 :: String -> Int -> [Char] -> Res String
    hex4 (a : b : c : d : cs) n acc
      | all isHex [a, b, c, d] =
          go cs (n + 4)
             (chr (((digitToInt a * 16 + digitToInt b) * 16
                    + digitToInt c) * 16 + digitToInt d) : acc)
    hex4 _ n _ = Bad n "expected four hex digits after \\u"

    isHex :: Char -> Bool
    isHex c = isDigit c || (c >= 'a' && c <= 'f')
              || (c >= 'A' && c <= 'F')

------------------------------------------------------------------
--  Numbers: exact decimal ratio -> one correctly rounded Double
------------------------------------------------------------------

pNumber :: String -> Int -> Res JValue
pNumber s0 n0 =
  case sign s0 n0 of
    (neg, s1, n1) ->
      case digits s1 n1 of
        ([], _, m) -> Bad m "expected digits"
        (ip, s2, n2) ->
          case frac s2 n2 of
            Bad m e -> Bad m e
            Good fp s3 n3 ->
              case expo s3 n3 of
                Bad m e -> Bad m e
                Good ex s4 n4 ->
                  Good (JNum (build neg ip fp ex)) s4 n4
  where
    sign :: String -> Int -> (Bool, String, Int)
    sign ('-' : cs) n = (True, cs, n + 1)
    sign s n = (False, s, n)

    digits :: String -> Int -> (String, String, Int)
    digits s n =
      case span isDigit s of
        (ds, rest) -> (ds, rest, n + length ds)

    frac :: String -> Int -> Res String
    frac ('.' : cs) n =
      case digits cs (n + 1) of
        ([], _, m) -> Bad m "expected digits after '.'"
        (ds, rest, m) -> Good ds rest m
    frac s n = Good "" s n

    expo :: String -> Int -> Res Int
    expo (e : cs) n
      | e == 'e' || e == 'E' =
          case esign cs (n + 1) of
            (neg, s1, n1) ->
              case digits s1 n1 of
                ([], _, m) -> Bad m "expected exponent digits"
                (ds, rest, m) ->
                  Good (if neg then negate (readInt ds)
                        else readInt ds) rest m
    expo s n = Good 0 s n

    esign :: String -> Int -> (Bool, String, Int)
    esign ('-' : cs) n = (True, cs, n + 1)
    esign ('+' : cs) n = (False, cs, n + 1)
    esign s n = (False, s, n)

    readInt :: String -> Int
    readInt = foldl (\a c -> a * 10 + digitToInt c) 0

    readInteger :: String -> Integer
    readInteger = foldl (\a c -> a * 10 + toInteger (digitToInt c)) 0

    build :: Bool -> String -> String -> Int -> Double
    build neg ip fp ex =
      let mant = readInteger (ip ++ fp)
          e10 = ex - length fp
          mag = if e10 >= 0
                then fromInteger (mant * 10 ^ e10)
                else fromRational (mant % (10 ^ negate e10))
      in if neg then negate mag else mag

------------------------------------------------------------------
--  Rendering: 2-space indent, ASCII-only output
------------------------------------------------------------------

{-# PRE  render \ind v -> ind >= 0 #-}
render :: Int -> JValue -> String
render _ JNull = "null"
render _ (JBool True) = "true"
render _ (JBool False) = "false"
render _ (JNum x) = renderNum x
render _ (JStr s) = renderStr s
render _ (JArr []) = "[]"
render ind (JArr vs) =
  "[\n"
  ++ intercalate ",\n"
       (map (\v -> pad (ind + 1) ++ render (ind + 1) v) vs)
  ++ "\n" ++ pad ind ++ "]"
render _ (JObj []) = "{}"
render ind (JObj ms) =
  "{\n"
  ++ intercalate ",\n"
       (map (\p -> pad (ind + 1) ++ renderStr (fst p) ++ ": "
                   ++ render (ind + 1) (snd p)) ms)
  ++ "\n" ++ pad ind ++ "}"

pad :: Int -> String
pad n = replicate (n * 2) ' '

--  Whole numbers of modest size print without the trailing ".0";
--  everything else uses show's shortest round-trip digits (valid
--  JSON: 1.0e7-style exponents are in the grammar).
renderNum :: Double -> String
renderNum x
  | isNaN x || isInfinite x = show x   -- 1e999 overflows; honest
  | otherwise =
      let r = round x :: Integer
      in if fromInteger r == x && abs x < 1.0e15
         then show r
         else show x

renderStr :: String -> String
renderStr s = "\"" ++ concatMap escC s ++ "\""
  where
    escC :: Char -> String
    escC c
      | c == '"' = "\\\""
      | c == '\\' = "\\\\"
      | c == '\n' = "\\n"
      | c == '\r' = "\\r"
      | c == '\t' = "\\t"
      | ord c == 8 = "\\b"
      | ord c == 12 = "\\f"
      | ord c < 32 || ord c > 126 = uEsc (ord c)
      | otherwise = [c]

    uEsc :: Int -> String
    uEsc v = "\\u" ++ map (intToDigit . (`mod` 16))
                          [ v `div` 4096, v `div` 256
                          , v `div` 16, v ]

------------------------------------------------------------------
--  Stats: object-key frequencies over the whole tree (Data.Map)
------------------------------------------------------------------

keyCounts :: JValue -> Map.Map String Int
keyCounts = go Map.empty
  where
    go :: Map.Map String Int -> JValue -> Map.Map String Int
    go m (JArr vs) = foldl go m vs
    go m (JObj ms) =
      foldl (\acc p -> go (bump (fst p) acc) (snd p)) m ms
    go m _ = m

    bump :: String -> Map.Map String Int -> Map.Map String Int
    bump k m = Map.insertWith (+) k 1 m

renderStats :: JValue -> String
renderStats v =
  let cs = Map.toList (keyCounts v)
      ordered = sortBy (\a b -> compare (negate (snd a), fst a)
                                        (negate (snd b), fst b)) cs
  in intercalate "\n"
       (map (\p -> show (snd p) ++ "  " ++ fst p) ordered)

------------------------------------------------------------------
--  Driver
------------------------------------------------------------------

runOn :: Bool -> String -> String
runOn stats text =
  case pValue text 0 of
    Bad m e -> "error at offset " ++ show m ++ ": " ++ e
    Good v rest m ->
      case skipWS rest m of
        ([], _) -> if stats then renderStats v else render 0 v
        (_, m2) -> "error at offset " ++ show m2
                   ++ ": trailing input after value"

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--stats", path] -> readFile path >>= putStrLn . runOn True
    [path] -> readFile path >>= putStrLn . runOn False
    [] -> getContents >>= putStrLn . runOn False
    _ -> putStrLn "usage: ajson [--stats] [FILE.json]"
