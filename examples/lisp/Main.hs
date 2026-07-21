module Main (main) where

import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (isEOF)

import Lisp.Val (Value (..), Env, showVal)
import Lisp.Parser (parseForms)
import Lisp.Eval (evalTop, primEnv)

--  mini-lisp: the AHC dogfood program. Two modes:
--    lisp            REPL over stdin (Ctrl-D exits)
--    lisp FILE.scm   batch: evaluate the file top to bottom
--  Both print the value of every top-level expression (definitions
--  are silent), so goldens are just captured stdout. Identical
--  behavior compiled by GHC or AHC is the whole point.

main :: IO ()
main = do
  args <- getArgs
  case bootEnv of
    Left err -> do
      putStrLn ("boot error: " ++ err)
      exitFailure
    Right g ->
      case args of
        [] -> do
          putStrLn "mini-lisp (an AHC example); Ctrl-D exits"
          repl g ""
        [path] -> do
          src <- readFile path
          runFile g src
        _ -> do
          putStrLn "usage: lisp [FILE.scm]"
          exitFailure

--  The REPL accumulates lines while a '(' is still open, so multi-
--  line forms work; the parser's "unclosed '('" message is the
--  continuation signal.
repl :: Env -> String -> IO ()
repl g pending = do
  eof <- isEOF
  if eof
    then return ()
    else do
      line <- getLine
      let src = pending ++ line ++ "\n"
      case parseForms src of
        Left err ->
          if err == "unclosed '('"
            then repl g src
            else do
              putStrLn ("error: " ++ err)
              repl g ""
        Right forms -> do
          g' <- runInteractive g forms
          repl g' ""

--  A REPL error abandons the rest of the line but keeps the session
--  (and every definition made so far).
runInteractive :: Env -> [Value] -> IO Env
runInteractive g [] = return g
runInteractive g (f : rest) =
  case evalTop g f of
    Left err -> do
      putStrLn ("error: " ++ err)
      return g
    Right (g', v) -> do
      printResult v
      runInteractive g' rest

runFile :: Env -> String -> IO ()
runFile g src =
  case parseForms src of
    Left err -> do
      putStrLn ("error: " ++ err)
      exitFailure
    Right forms -> runBatch g forms

runBatch :: Env -> [Value] -> IO ()
runBatch _ [] = return ()
runBatch g (f : rest) =
  case evalTop g f of
    Left err -> do
      putStrLn ("error: " ++ err)
      exitFailure
    Right (g', v) -> do
      printResult v
      runBatch g' rest

printResult :: Value -> IO ()
printResult VUnit = return ()
printResult v = putStrLn (showVal v)

--  ---------------------------------------------------------------
--  The boot prelude: library functions defined in mini-lisp itself,
--  evaluated once at startup. Note map/filter need no `apply`
--  primitive - `f` is applied by ordinary application.

bootEnv :: Either String Env
bootEnv =
  case parseForms bootSrc of
    Left err -> Left err
    Right forms -> runQuiet primEnv forms

runQuiet :: Env -> [Value] -> Either String Env
runQuiet g [] = Right g
runQuiet g (f : rest) =
  case evalTop g f of
    Left err -> Left err
    Right (g', _) -> runQuiet g' rest

bootSrc :: String
bootSrc = unlines
  [ "(define (map f xs)"
  , "  (if (null? xs) '() (cons (f (car xs)) (map f (cdr xs)))))"
  , "(define (filter p xs)"
  , "  (cond ((null? xs) '())"
  , "        ((p (car xs)) (cons (car xs) (filter p (cdr xs))))"
  , "        (else (filter p (cdr xs)))))"
  , "(define (fold-left f acc xs)"
  , "  (if (null? xs) acc (fold-left f (f acc (car xs)) (cdr xs))))"
  , "(define (fold-right f init xs)"
  , "  (if (null? xs) init (f (car xs) (fold-right f init (cdr xs)))))"
  , "(define (assoc k ps)"
  , "  (cond ((null? ps) #f)"
  , "        ((equal? k (car (car ps))) (car ps))"
  , "        (else (assoc k (cdr ps)))))"
  , "(define (member x xs)"
  , "  (cond ((null? xs) #f)"
  , "        ((equal? x (car xs)) xs)"
  , "        (else (member x (cdr xs)))))"
  , "(define (cadr x) (car (cdr x)))"
  , "(define (caddr x) (car (cdr (cdr x))))"
  , "(define (range a b)"
  , "  (if (>= a b) '() (cons a (range (+ a 1) b))))"
  , "(define (sum xs) (fold-left + 0 xs))"
  ]
