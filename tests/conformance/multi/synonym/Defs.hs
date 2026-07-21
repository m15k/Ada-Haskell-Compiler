module Defs (Env, Table, none, extend) where

--  Type synonyms exported across a module boundary - both nullary
--  (Env) and parametric (Table a). Pins the arena-confusion bug
--  found by the examples/lisp dogfood program: importers must
--  expand the cached Core rhs, never this module's syntax arena.
type Env = [(String, Integer)]
type Table a = [(String, a)]

none :: Env
none = []

extend :: String -> Integer -> Env -> Env
extend k v e = (k, v) : e
