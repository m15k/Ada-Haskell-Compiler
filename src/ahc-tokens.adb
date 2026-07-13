package body AHC.Tokens is

   Reserved_Word_Text : constant array (Reserved_Word_Kind) of
     access constant String :=
       [Kw_Case     => new String'("case"),
        Kw_Class    => new String'("class"),
        Kw_Data     => new String'("data"),
        Kw_Default  => new String'("default"),
        Kw_Deriving => new String'("deriving"),
        Kw_Do       => new String'("do"),
        Kw_Else     => new String'("else"),
        Kw_Foreign  => new String'("foreign"),
        Kw_If       => new String'("if"),
        Kw_Import   => new String'("import"),
        Kw_In       => new String'("in"),
        Kw_Infix    => new String'("infix"),
        Kw_Infixl   => new String'("infixl"),
        Kw_Infixr   => new String'("infixr"),
        Kw_Instance => new String'("instance"),
        Kw_Let      => new String'("let"),
        Kw_Module   => new String'("module"),
        Kw_Newtype  => new String'("newtype"),
        Kw_Of       => new String'("of"),
        Kw_Then     => new String'("then"),
        Kw_Type     => new String'("type"),
        Kw_Where    => new String'("where"),
        Underscore  => new String'("_")];

   Reserved_Op_Text : constant array (Reserved_Op_Kind) of
     access constant String :=
       [Dot_Dot     => new String'(".."),
        Colon       => new String'(":"),
        Colon_Colon => new String'("::"),
        Equals      => new String'("="),
        Backslash   => new String'("\"),
        Pipe        => new String'("|"),
        Left_Arrow  => new String'("<-"),
        Right_Arrow => new String'("->"),
        At_Sign     => new String'("@"),
        Tilde       => new String'("~"),
        Fat_Arrow   => new String'("=>")];

   function Name_Text (T : Token; Table : Names.Name_Table) return String
   is (if T.Kind in Qualified_Kind
       then Table.Text (T.Qualifier) & "." & Table.Text (T.Name)
       else Table.Text (T.Name));

   function Image (T : Token; Table : Names.Name_Table) return String is
   begin
      case T.Kind is
         when Reserved_Word_Kind =>
            return Reserved_Word_Text (T.Kind).all;
         when Reserved_Op_Kind =>
            return Reserved_Op_Text (T.Kind).all;
         when Varid   => return "varid """ & Name_Text (T, Table) & """";
         when Conid   => return "conid """ & Name_Text (T, Table) & """";
         when Varsym  => return "varsym """ & Name_Text (T, Table) & """";
         when Consym  => return "consym """ & Name_Text (T, Table) & """";
         when Qvarid  => return "qvarid """ & Name_Text (T, Table) & """";
         when Qconid  => return "qconid """ & Name_Text (T, Table) & """";
         when Qvarsym => return "qvarsym """ & Name_Text (T, Table) & """";
         when Qconsym => return "qconsym """ & Name_Text (T, Table) & """";
         when Int_Lit =>
            return "int """ & Table.Text (T.Int_Text) & """";
         when Float_Lit =>
            return "float """ & Table.Text (T.Float_Text) & """";
         when Char_Lit =>
            if T.Char_Value in 16#20# .. 16#7E# then
               return "char '" & Character'Val (T.Char_Value) & "'";
            else
               declare
                  Img : constant String := T.Char_Value'Image;
               begin
                  return "char \" & Img (2 .. Img'Last);
               end;
            end if;
         when String_Lit =>
            return "string """
              & (if T.String_Value = Names.No_Name then ""
                 else Table.Text (T.String_Value))
              & """";
         when Left_Paren    => return "(";
         when Right_Paren   => return ")";
         when Left_Bracket  => return "[";
         when Right_Bracket => return "]";
         when Comma         => return ",";
         when Semicolon     => return ";";
         when Backtick      => return "`";
         when Left_Brace    => return "{";
         when Right_Brace   => return "}";
         when V_Left_Brace  => return "{v";
         when V_Right_Brace => return "}v";
         when V_Semicolon   => return ";v";
         when End_Of_File   => return "<eof>";
         when Error_Token   => return "<error>";
      end case;
   end Image;

end AHC.Tokens;
