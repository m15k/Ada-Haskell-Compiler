-- AHC's ONE packed string type: an immutable UTF-8 byte slice
-- (AHC_BYTES at runtime), serving both the text and byte roles GHC
-- splits across Text/ByteString. The API indexes by CODE POINT;
-- internally offsets are bytes, so byteLength and take/drop slices
-- are O(1) shares of the parent payload while length/index are O(n)
-- scans. Eq/Ord/Show come from the builtin instances (byte order
-- over valid UTF-8 IS code-point order). The `Text` type name is
-- wired into the compiler like `Int` (a documented divergence:
-- visible without import; the functions here still need the
-- import). Import qualified - length/take/drop/null/concat/splitAt
-- collide with the Prelude:
--
--   import qualified Data.Text as T
module Data.Text
  ( Text
  , pack, unpack
  , empty, singleton
  , append, concat, intercalate
  , length, byteLength, null
  , index, take, drop, splitAt
  , putText, putTextLn, readFileText, writeFileText
  , textFromCStringLen, textNewCString
  ) where

import Prelude hiding (concat, length, null, take, drop, splitAt)

pack :: String -> Text
pack = primTextPack

unpack :: Text -> String
unpack = primTextUnpack

empty :: Text
empty = primTextPack ""

singleton :: Char -> Text
singleton c = primTextPack [c]

append :: Text -> Text -> Text
append = primTextAppend

concat :: [Text] -> Text
concat = foldr primTextAppend empty

intercalate :: Text -> [Text] -> Text
intercalate _ []       = empty
intercalate _ [t]      = t
intercalate sep (t:ts) = append t (append sep (intercalate sep ts))

-- Code points, O(n).
length :: Text -> Int
length = primTextLength

-- Bytes, O(1).
byteLength :: Text -> Int
byteLength = primTextByteLength

null :: Text -> Bool
null t = byteLength t == 0

-- Dies on out-of-range, like GHC's Data.Text.index.
index :: Text -> Int -> Char
index = primTextIndex

-- O(n) scan to the split point, O(1) slice sharing the payload.
take :: Int -> Text -> Text
take = primTextTake

drop :: Int -> Text -> Text
drop = primTextDrop

splitAt :: Int -> Text -> (Text, Text)
splitAt n t = (take n t, drop n t)

-- IO is Handle-free by design (Handle's constructor is private to
-- System.IO); one fwrite of the slice, no cons-list walk. Input
-- normalizes to the valid-UTF-8 payload invariant (invalid bytes
-- become U+FFFD, the runtime's one replacement rule).
putText :: Text -> IO ()
putText = primTextPut

putTextLn :: Text -> IO ()
putTextLn t = putText t >> putStrLn ""

readFileText :: String -> IO Text
readFileText = primTextReadFile

writeFileText :: String -> Text -> IO ()
writeFileText = primTextWriteFile

-- C bridges, mirroring peekCStringLen/newCString: exactly n bytes
-- in (normalized), malloc'd NUL-terminated copy out (caller frees).
textFromCStringLen :: Ptr Char -> Int -> IO Text
textFromCStringLen = primTextFromCStringLen

textNewCString :: Text -> IO (Ptr Char)
textNewCString = primTextNewCString
