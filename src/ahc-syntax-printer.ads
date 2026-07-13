--  Canonical, deterministic AST dump: one S-expression per top-level
--  element, fully parenthesized, no ids, no spans. This is the output
--  of `ahc parse` and the golden-test format, so its stability matters
--  more than its beauty.

package AHC.Syntax.Printer is

   function Dump
     (A : Module_Arena; Table : Names.Name_Table) return String;

end AHC.Syntax.Printer;
