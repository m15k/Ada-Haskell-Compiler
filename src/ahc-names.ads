--  Interned strings. Every identifier, operator, and literal payload in
--  the compiler is a Name_Id into one Name_Table; equality is integer
--  equality and the ids are stable, printable, and map-key friendly.

private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Containers.Indefinite_Vectors;
private with Ada.Strings.Hash;

package AHC.Names is

   type Name_Id is new Natural;

   No_Name : constant Name_Id := 0;

   subtype Real_Name_Id is Name_Id range 1 .. Name_Id'Last;

   type Name_Table is tagged limited private;

   function Last_Id (T : Name_Table) return Name_Id;

   function Intern (T : in out Name_Table; S : String) return Real_Name_Id
     with Post => Intern'Result <= T.Last_Id
                  and then T.Text (Intern'Result) = S;

   function Text (T : Name_Table; Id : Real_Name_Id) return String
     with Pre => Id <= T.Last_Id;

private

   package Id_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Real_Name_Id,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Text_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Real_Name_Id, Element_Type => String);

   type Name_Table is tagged limited record
      By_Text : Id_Maps.Map;
      By_Id   : Text_Vectors.Vector;
   end record;

end AHC.Names;
