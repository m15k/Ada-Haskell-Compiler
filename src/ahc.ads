--  Root package of the Ada Haskell Compiler (AHC).
--
--  AHC is a batch compiler for Haskell 2010 written in Ada 2022, built
--  around Design-by-Contract: every phase states its invariants as
--  checkable contracts, enabled in development/validation builds.

package AHC with Pure is

   Version : constant String := "1.2.0";

end AHC;
