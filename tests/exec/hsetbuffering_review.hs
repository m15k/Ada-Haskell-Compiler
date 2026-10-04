-- hSetBuffering / hSetEcho, the M142 review round: a block size <= 0
-- is GHC's "illegal buffer size" IOError (and leaves the mode alone),
-- any Int size reads back exactly (maxBound included), switching the
-- mode of an input stream that has already been read loses no
-- buffered input, and the closed-handle errors name the file - at
-- hIsTerminalDevice for hSetEcho/hGetEcho, as GHC. Reads stdin from
-- the .stdin file; every stdout write is flushed.
import System.IO
import Control.Exception
import System.Directory (removeFile)

say :: String -> IO ()
say s = putStrLn s >> hFlush stdout

t :: Show a => String -> IO a -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> say (name ++ ": " ++ show (e :: IOException))
    Right v -> say (name ++ ": " ++ show v)

main :: IO ()
main = do
  l1 <- getLine
  hSetBuffering stdin NoBuffering
  l2 <- getLine
  c <- getChar
  hSetBuffering stdin (BlockBuffering (Just 3))
  l3 <- getLine
  hSetBuffering stdin LineBuffering
  l4 <- getLine
  say (show (l1, l2, c, l3, l4))
  t "stdin mode" (hGetBuffering stdin)
  t "size 0" (hSetBuffering stdout (BlockBuffering (Just 0)))
  t "size -1" (hSetBuffering stdout (BlockBuffering (Just (-1))))
  t "size minBound" (hSetBuffering stdout (BlockBuffering (Just minBound)))
  t "after errors" (hGetBuffering stdout)
  t "size maxBound" (hSetBuffering stdout (BlockBuffering (Just maxBound)))
  t "reads back" (hGetBuffering stdout)
  t "size 2^32+1" (hSetBuffering stdout (BlockBuffering (Just 4294967297)))
  t "reads back" (hGetBuffering stdout)
  mapM_ (say . show) [1 .. 3 :: Int]
  hSetBuffering stdout LineBuffering
  h <- openFile "hsetbuffering_review.tmp" WriteMode
  hSetBuffering h (BlockBuffering (Just 2147483649))
  hPutStr h (replicate 100000 'x')
  hClose h
  t "closed hSetBuffering" (hSetBuffering h NoBuffering)
  t "closed size 0" (hSetBuffering h (BlockBuffering (Just 0)))
  t "closed hGetBuffering" (hGetBuffering h)
  t "closed hSetEcho" (hSetEcho h True)
  t "closed hGetEcho" (hGetEcho h)
  t "closed hPutStr" (hPutStr h "x")
  t "not a tty: hGetEcho" (hGetEcho stdin)
  t "not a tty: hSetEcho" (hSetEcho stdin False)
  s <- readFile "hsetbuffering_review.tmp"
  say (show (length s))
  h2 <- openFile "hsetbuffering_review.tmp" ReadMode
  a <- hGetChar h2
  hSetBuffering h2 NoBuffering
  b <- hGetChar h2
  hSetBuffering h2 (BlockBuffering Nothing)
  rest <- hGetContents h2
  say (show (a, b, length rest))
  hClose h2
  h3 <- openFile "hsetbuffering_review2.tmp" WriteMode
  t "a reused slot: the old handle keeps its name" (hGetLine h2)
  hClose h3
  t "and the new one has its own" (hPutStr h3 "y")
  removeFile "hsetbuffering_review.tmp"
  removeFile "hsetbuffering_review2.tmp"
