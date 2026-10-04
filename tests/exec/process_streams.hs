-- System.Process, the M142 review round: readProcess inherits stderr
-- (only stdout is captured), readProcessWithExitCode captures both,
-- stdin is fed lazily (an infinite input to a child that stops
-- reading), `system ""` is GHC's null-command error, captured output
-- that is not UTF-8 is hGetContents' decoding error naming the pipe
-- "fd:N" (N masked here: a compiled program started with only 0..2
-- open names fd:5 / fd:7 under both compilers, but the number follows
-- whatever fds the harness leaves open), a raise inside the stdin
-- String propagates, and a failing waitpid (SIGCHLD ignored, so the
-- child is reaped by the kernel) is waitForProcess' IOError. Every
-- stdout write is flushed, so the 2>&1 capture shows the order.
{-# LANGUAGE ForeignFunctionInterface #-}
import System.Process
import System.IO
import Control.Exception
import Foreign.Ptr
import Foreign.C.Types

foreign import ccall "signal" c_signal :: CInt -> Ptr () -> IO (Ptr ())

say :: String -> IO ()
say s = putStrLn s >> hFlush stdout

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> say (name ++ ": " ++ maskFd (show (e :: SomeException)))
    Right () -> say (name ++ ": ok")

maskFd :: String -> String
maskFd ('f' : 'd' : ':' : rest) = "fd:N" ++ maskFd (dropWhile (`elem` "0123456789") rest)
maskFd (c : cs) = c : maskFd cs
maskFd [] = []

main :: IO ()
main = do
  o <- readProcess "sh" ["-c", "echo to-stderr >&2; echo out"] ""
  say ("readProcess: " ++ show o)
  readProcessWithExitCode "sh" ["-c", "echo out; echo err >&2; exit 3"] "" >>= say . show
  readProcessWithExitCode "head" ["-c", "3"] (cycle "x") >>= say . show
  readProcessWithExitCode "head" ["-c", "5"] ("ab" ++ cycle "y") >>= say . show
  readProcess "sh" ["-c", "exec 0<&-; echo closed-stdin"] (cycle "z") >>= say . show
  readProcess "cat" [] "h\233llo \8364 \128512" >>= say . show
  t "system empty" (system "" >>= say . show)
  t "callCommand empty" (callCommand "")
  t "bad utf8 readProcess" (readProcess "printf" ["\\377abc"] "" >>= say . show)
  t "bad utf8 rpwec" (readProcessWithExitCode "printf" ["\\377abc"] "" >>= say . show)
  t "bad utf8 stderr" (readProcessWithExitCode "sh" ["-c", "printf '\\376x' >&2"] "" >>= say . show)
  t "truncated utf8" (readProcess "printf" ["ab\\303"] "" >>= say . show)
  t "surrogate utf8" (readProcess "printf" ["ab\\355\\240\\200z"] "" >>= say . show)
  t "overlong utf8" (readProcess "printf" ["ab\\300\\200z"] "" >>= say . show)
  t "raise in stdin" (readProcess "cat" [] ("abc" ++ error "boom") >>= say . show)
  t "raise in stdin, child ignores it" (readProcess "true" [] ("abc" ++ error "boom2") >>= say . show)
  _ <- c_signal 20 (nullPtr `plusPtr` 1)
  t "waitpid fails" (readProcessWithExitCode "false" [] "" >>= say . show)
  t "system, waitpid fails" (system "exit 3" >>= say . show)
