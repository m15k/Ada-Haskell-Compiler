-- Packed-Text traffic, paired against b_strings.hs: append/length
-- on slices in a hot loop, where [Char] pays per-node costs and
-- Text pays memcpy + O(1) slicing.
import qualified Data.Text as T

main :: IO ()
main = print (go 10000 (T.pack "") 0)
  where
    seed = T.pack "the quick brown fox jumps over the lazy dog, "
    go :: Int -> T.Text -> Int -> Int
    go 0 _ acc = acc
    go n t acc =
      let t' = T.take 64 (T.append (T.drop 3 seed) t)
          w  = T.length t' + T.byteLength t'
      in go (n - 1) t' (acc + w + T.length (T.take 8 seed))
