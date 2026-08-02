module Text.Read (Read (..), reads, read) where

--  Report 9.1 exports Read (..), reads and read from the Prelude, so
--  the class, its instances and the readsEnum_ derive support now live
--  in prelude/Prelude.hs. This module stays as the facade the Report
--  also requires: it re-exports those Prelude entities, so
--  `import Text.Read` and the implicit Prelude name the same things.
