package body AHC.Names is

   function Last_Id (T : Name_Table) return Name_Id
   is (if T.By_Id.Is_Empty then No_Name else T.By_Id.Last_Index);

   function Intern (T : in out Name_Table; S : String) return Real_Name_Id is
      Position : constant Id_Maps.Cursor := T.By_Text.Find (S);
   begin
      if Id_Maps.Has_Element (Position) then
         return Id_Maps.Element (Position);
      end if;
      T.By_Id.Append (S);
      T.By_Text.Insert (S, T.By_Id.Last_Index);
      return T.By_Id.Last_Index;
   end Intern;

   function Text (T : Name_Table; Id : Real_Name_Id) return String
   is (T.By_Id (Id));

end AHC.Names;
