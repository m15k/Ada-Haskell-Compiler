--  Canonical Core dump: one S-expression per top-level binding group,
--  deterministic (vars print as name_<id>), no meta-variable leakage
--  expected after typechecking. Output of `ahc core`; golden format
--  core_*.core.

package AHC.Core.Printer is

   --  Dump top-level binding groups starting at From_Group (lets the
   --  driver hide the compiled Prelude when showing user Core).
   function Dump
     (M : Core_Module; Table : Names.Name_Table;
      From_Group : Positive := 1) return String;

   --  Render one type (used by `ahc check` and the tests).
   function Type_Image
     (M : Core_Module; Table : Names.Name_Table; T : Real_Type_Id)
      return String
     with Pre => T <= M.Last_Type;

   function Scheme_Image
     (M : Core_Module; Table : Names.Name_Table; S : Real_Scheme_Id)
      return String
     with Pre => S <= M.Last_Scheme;

   --  Human-readable Haskell form for `ahc check`:
   --  "(Eq a, Num b) => [a] -> b -> Bool" - tyvars renamed a, b, c...
   --  in order of first occurrence, lists/tuples/arrows in standard
   --  notation, forall-free.
   function Pretty_Scheme
     (M : Core_Module; Table : Names.Name_Table; S : Real_Scheme_Id)
      return String
     with Pre => S <= M.Last_Scheme;

end AHC.Core.Printer;
