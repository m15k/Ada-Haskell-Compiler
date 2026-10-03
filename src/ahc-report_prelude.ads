--  The names GHC's Prelude exports. AHC's Prelude is a superset
--  (fromMaybe, swap, internal helpers), so an own declaration is
--  ambiguous with the Prelude (Report 5.5.2, M144) only for names
--  in this table. Kind: 'V' value or operator, 'T' type, class or
--  synonym, 'C' data constructor. The body is generated.
package AHC.Report_Prelude is

   function Exports (Kind : Character; Name : String) return Boolean;

end AHC.Report_Prelude;
