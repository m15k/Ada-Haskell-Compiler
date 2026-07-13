with AHC.Names;  use AHC.Names;
with AHC.Tokens; use AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Tokens is

   Table : Name_Table;

   procedure Unqualified_With_Qualifier is
      T : Token :=
        (Kind => Varid, Name => Table.Intern ("x"),
         Qualifier => Table.Intern ("M"), others => <>);
      pragma Unreferenced (T);
   begin
      null;
   end Unqualified_With_Qualifier;

   procedure Run is
   begin
      Start_Suite ("Tokens");

      Check (Kw_Let in Layout_Keyword_Kind
             and then Kw_Where in Layout_Keyword_Kind
             and then Kw_Do in Layout_Keyword_Kind
             and then Kw_Of in Layout_Keyword_Kind,
             "layout keywords are let/where/do/of");
      Check (Kw_If not in Layout_Keyword_Kind,
             "'if' is not a layout keyword");
      Check (V_Semicolon in Virtual_Kind and Semicolon not in Virtual_Kind,
             "virtual kinds are distinct from real ones");

      declare
         T : constant Token :=
           (Kind => Varid, Name => Table.Intern ("length"), others => <>);
      begin
         Check_Equal (Image (T, Table), "varid ""length""", "varid image");
      end;

      declare
         T : constant Token :=
           (Kind      => Qconid,
            Name      => Table.Intern ("Map"),
            Qualifier => Table.Intern ("Data"),
            others    => <>);
      begin
         Check_Equal (Image (T, Table), "qconid ""Data.Map""",
                      "qualified name image");
      end;

      declare
         T : constant Token :=
           (Kind => Int_Lit, Int_Text => Table.Intern ("0x1F"),
            others => <>);
      begin
         Check_Equal (Image (T, Table), "int ""0x1F""",
                      "int literal keeps its radix spelling");
      end;

      Check_Equal
        (Image ((Kind => Kw_Where, others => <>), Table), "where",
         "keyword image");
      Check_Equal
        (Image ((Kind => Fat_Arrow, others => <>), Table), "=>",
         "reserved op image");
      Check_Equal
        (Image ((Kind => V_Left_Brace, others => <>), Table), "{v",
         "virtual open brace image");

      Check_Assertion_Error
        (Unqualified_With_Qualifier'Access,
         "unqualified token with qualifier violates predicate");
   end Run;

end Test_Tokens;
