--  The interactive loop: compile-and-run over the object cache.
--  Design: docs/repl-design-note.md. The REPL adds no evaluator -
--  every entry becomes a real program built by the real pipeline
--  and executed by the real runtime.

package AHC.Repl is

   procedure Run;

end AHC.Repl;
