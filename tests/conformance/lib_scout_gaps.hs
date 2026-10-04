-- Library gaps the M142 repo scout hit (hangman programs): forever,
-- foldM_, liftM3, (<$!>) from Control.Monad; isLetter and the cheap
-- Data.Char predicates; hSetBuffering/hGetBuffering and BufferMode.
import Control.Monad
import Data.Char
import System.IO
import Data.IORef
import System.IO.Error (catchIOError)

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  b <- hGetBuffering stdout
  print b
  hSetBuffering stdout LineBuffering
  hGetBuffering stdout >>= print
  print [NoBuffering, LineBuffering, BlockBuffering Nothing, BlockBuffering (Just 4096)]
  print (NoBuffering == NoBuffering, LineBuffering < BlockBuffering Nothing)
  r <- newIORef (0 :: Int)
  let loop = forever (do { n <- readIORef r; when (n >= 3) (ioError (userError "stop")); writeIORef r (n + 1) })
  loop `catchIOError` (\e -> putStrLn ("forever stopped: " ++ show e))
  foldM_ (\acc x -> print (acc + x) >> return (acc + x)) 0 [1, 2, 3 :: Int]
  print =<< liftM3 (\a b c -> a + b + c) (return 1) (return 2) (return (3 :: Int))
  x <- (+ 1) <$!> return (41 :: Int)
  print x
  print (map isLetter "aZ1 _é", map isAscii "a\200", map isLatin1 "a\255\256")
  print (map isControl "\0\31 \127\159\160", map isAsciiUpper "AaÀ", map isAsciiLower "aAà")
