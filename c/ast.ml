(****************************************************************************)
(*                           the diy toolsuite                              *)
(*                                                                          *)
(* Jade Alglave, University College London, UK.                             *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                          *)
(*                                                                          *)
(* Copyright 2010-present Institut National de Recherche en Informatique et *)
(* en Automatique and the authors. All rights reserved.                     *)
(*                                                                          *)
(* This software is governed by the CeCILL-B license under French law and   *)
(* abiding by the rules of distribution of free software. You can use,      *)
(* modify and/ or redistribute the software under the terms of the CeCILL-B *)
(* license as circulated by CEA, CNRS and INRIA at the following URL        *)
(* "http://www.cecill.info". We also give a copy in LICENSE.txt.            *)
(****************************************************************************)

type param = { param_ty : C_type.t; param_name : string }

type 'body test =
  { proc : int
  ; params : param list
  ; body : 'body
  }

type 'body t =
  | Global of string
  | Test of 'body test

(* New AST, under construction *)

module Identifier = struct
  type t = string
end

module Constant = struct
  type t =
    | Char    of char
    | Float   of float
    | Integer of int
    | String  of string
  ;;
end

module Operator = struct
  type assign =
    [ `Assign
    | `Assign_mul
    | `Assign_div
    | `Assign_mod
    | `Assign_add
    | `Assign_sub
    | `Assign_shl
    | `Assign_shr
    | `Assign_and
    | `Assign_xor
    | `Assign_or
    ]
  ;;

  type bin =
    [ assign
    | `Mul
    | `Div
    | `Mod
    | `Add
    | `Sub
    | `Shl
    | `Shr
    | `And
    | `Xor
    | `Or
    | `Land
    | `Lor
    | `Lt
    | `Le
    | `Eq
    | `Ge
    | `Gt
    | `Ne
    ]
  ;;

  type pre =
    [ `Inc        (* ++ *)
    | `Dec        (* -- *)
    | `Sizeof_val (* sizeof *)
    | `Ref        (* & *)
    | `Deref      (* * *)
    | `Add        (* + *)
    | `Sub        (* - *)
    | `Not        (* ~ *)
    | `Lnot       (* ! *)
    ]
  ;;

  type post =
    [ `Inc (* ++ *)
    | `Dec (* -- *)
    ]
  ;;
end

module type S_decl = sig
  type q
  type d

  type t =
    { qualifiers : q list
    ; declarator : d
    }
  ;;
end

module Type_qual = struct
  type t =
    [ `Const
    | `Volatile
    ]
  ;;
end

module Prim_type = struct
  type t =
    [ `Void
    | `Char
    | `Short
    | `Int
    | `Long
    | `Float
    | `Double
    | `Signed
    | `Unsigned
    ]
end

module Storage_class_spec = struct
  type t =
    [ `Auto
    | `Register
    | `Static
    | `Extern
    | `Typedef
    ]
  ;;
end

module type S_expr = sig
  type ty

  type t =
    | Prefix      of Operator.pre * t
    | Postfix     of t * Operator.post
    | Binary      of t * Operator.bin * t
    | Cast        of ty * t
    | Subscript   of { array : t; index : t }
    | Field       of { value  : t
                     ; field  : Identifier.t
                     ; access : [ `Direct (* . *) | `Deref (* -> *) ]
                     }
    | Sizeof_type of ty
    | Identifier  of Identifier.t
    | String      of String.t
    | Constant    of Constant.t
    | Brackets    of t
  ;;
end

module Pointer = struct
  type t = (Type_qual.t list) list
end

module type S_direct_declarator = sig
  type dec
  type par
  type expr

  type t =
    | Id of Identifier.t
    | Bracket of dec
    | Array of t * expr option
    | Fun_decl of t * par list
    | Fun_call of t * Identifier.t list
  ;;
end

module type S_declarator = sig
  type ddec

  type t =
    { pointer : Pointer.t option
    ; direct  : ddec
    }
  ;;
end

module type S_struct_declarator = sig
  type dec
  type expr

  type t =
    | Regular of dec
    | Bitfield of dec option * expr
  ;;
end


module type S_type_spec = sig
  type su
  type en

  type t =
    [ Prim_type.t
    | `Struct_or_union of su
    | `Enum of en
    | `Defined_type of Identifier.t
    ]
  ;;
end

module type S_composite_spec = sig
  type ty
  type dec

  type t =
    | Literal of
        { ty       : ty
        ; name_opt : Identifier.t option
        ; decls    : dec list
        }
    | Named of ty * Identifier.t
end


module type S_direct_abs_declarator = sig
  type dec
  type par
  type expr

  type t =
    | Bracket of dec
    | Array of t option * expr option
    | Fun_decl of t option * par list
  ;;
end

module type S_abs_declarator = sig
  type ddec

  type t =
    | Pointer of Pointer.t
    | Direct of Pointer.t option * ddec
  ;;
end

module rec Expr : S_expr
  with type ty := Type_name.t = struct
  type t =
    | Prefix      of Operator.pre * t
    | Postfix     of t * Operator.post
    | Binary      of t * Operator.bin * t
    | Cast        of Type_name.t * t
    | Subscript   of { array : t; index : t }
    | Field       of { value  : t
                     ; field  : Identifier.t
                     ; access : [ `Direct (* . *) | `Deref (* -> *) ]
                     }
    | Sizeof_type of Type_name.t
    | Identifier  of Identifier.t
    | String      of String.t
    | Constant    of Constant.t
    | Brackets    of t
  ;;
end
and Enumerator : sig
  type t =
    { name  : Identifier.t
    ; value : Expr.t option
    }
  ;;
end = struct
  type t =
    { name  : Identifier.t
    ; value : Expr.t option
    }
  ;;
end
and Enum_spec
  : S_composite_spec
    with type ty  := [`Enum]
     and type dec := Enumerator.t = struct
  type t =
    | Literal of
        { ty       : [`Enum]
        ; name_opt : Identifier.t option
        ; decls    : Enumerator.t list
        }
    | Named of [`Enum] * Identifier.t
end
and Struct_decl : S_decl
  with type q := [ Type_spec.t | Type_qual.t ]
   and type d := Struct_declarator.t list = struct
  type t =
    { qualifiers : [ Type_spec.t | Type_qual.t ] list
    ; declarator : Struct_declarator.t list
    }
  ;;
end
and Type_spec : S_type_spec
  with type su := Struct_or_union_spec.t
   and type en := Enum_spec.t = struct
  type t =
    [ `Void
    | `Char
    | `Short
    | `Int
    | `Long
    | `Float
    | `Double
    | `Signed
    | `Unsigned
    | `Struct_or_union of Struct_or_union_spec.t
    | `Enum of Enum_spec.t
    | `Defined_type of Identifier.t
    ]
  ;;
end
and Type_name : S_decl
  with type q := Decl_spec.t
   and type d := Abs_declarator.t option = struct
  type t =
    { qualifiers : Decl_spec.t list
    ; declarator : Abs_declarator.t option
    }
  ;;
end
and Struct_or_union_spec : S_composite_spec
  with type ty  := [`Struct | `Union]
   and type dec := Struct_decl.t = struct
  type t =
    | Literal of
        { ty       : [`Struct | `Union]
        ; name_opt : Identifier.t option
        ; decls    : Struct_decl.t list
        }
    | Named of [`Struct | `Union] * Identifier.t
end
and Decl_spec : sig
  type t =
    [ Storage_class_spec.t
    | Type_spec.t
    | Type_qual.t
    ]
  ;;
end = struct
  type t =
    [ Storage_class_spec.t
    | Type_spec.t
    | Type_qual.t
    ]
  ;;
end
and Param_decl : S_decl
  with type q := Decl_spec.t
   and type d := [ `Concrete of Declarator.t
                 | `Abstract of Abs_declarator.t option
                 ] = struct
  type t =
    { qualifiers : Decl_spec.t list
    ; declarator : [ `Concrete of Declarator.t
                   | `Abstract of Abs_declarator.t option
                   ]
    }
  ;;
end
and Param : sig
  type t = Param_decl.t list
end = struct
  type t = Param_decl.t list
end
and Param_type : sig
  type t =
    { params : Param.t list
    ; style  : [`Normal | `Variadic]
    }
end = struct
  type t =
    { params : Param.t list
    ; style  : [`Normal | `Variadic]
    }
  ;;
end
and Direct_declarator : S_direct_declarator
  with type dec  := Declarator.t
   and type par  := Param_type.t
   and type expr := Expr.t = struct
  type t =
    | Id of Identifier.t
    | Bracket of Declarator.t
    | Array of t * Expr.t option
    | Fun_decl of t * Param_type.t list
    | Fun_call of t * Identifier.t list
end
and Declarator : S_declarator
  with type ddec := Direct_declarator.t = struct
  type t =
    { pointer : Pointer.t option
    ; direct  : Direct_declarator.t
    }
  ;;
end
and Struct_declarator : S_struct_declarator
  with type dec  := Declarator.t
   and type expr := Expr.t = struct
  type t =
    | Regular of Declarator.t
    | Bitfield of Declarator.t option * Expr.t
  ;;
end
and Direct_abs_declarator : S_direct_abs_declarator
  with type dec  := Abs_declarator.t
   and type par  := Param_type.t
   and type expr := Expr.t = struct
  type t =
    | Bracket of Abs_declarator.t
    | Array of t option * Expr.t option
    | Fun_decl of t option * Param_type.t list
end
and Abs_declarator
  : S_abs_declarator with type ddec := Direct_abs_declarator.t = struct
  type t =
    | Pointer of Pointer.t
    | Direct of Pointer.t option * Direct_abs_declarator.t
  ;;
end

module Initialiser = struct
  type t =
    | Assign of Expr.t
    | List of t list
  ;;
end

module Init_declarator = struct
  type t =
    { declarator : Declarator.t
    ; initialiser : Initialiser.t option
    }
  ;;
end

module Decl : S_decl
  with type q := Decl_spec.t
   and type d := Init_declarator.t list = struct
  type t =
    { qualifiers  : Decl_spec.t list
    ; declarator  : Init_declarator.t list
    }
  ;;
end

module Label = struct
  type t =
    | Normal of Identifier.t
    | Case   of Expr.t
    | Default
  ;;
end

module type S_stm = sig
  type com

  type t =
    | Label of Label.t * t
    | Expr of Expr.t option
    | Compound of com
    | If of
        { cond : Expr.t
        ; t_branch : t
        ; f_branch : t option
        }
    | Switch of Expr.t * t
    | While of Expr.t * t
    | Do_while of t * Expr.t
    | For of
        { init   : Expr.t option
        ; cond   : Expr.t option
        ; update : Expr.t option
        ; body   : t
        }
end

module type S_compound_stm = sig
  type stm

  type t =
    { decls : Decl.t list
    ; stms  : stm list
    }
  ;;
end

module rec Stm : S_stm
  with type com := Compound_stm.t = struct
  type t =
    | Label of Label.t * t
    | Expr of Expr.t option
    | Compound of Compound_stm.t
    | If of
        { cond : Expr.t
        ; t_branch : t
        ; f_branch : t option
        }
    | Switch of Expr.t * t
    | While of Expr.t * t
    | Do_while of t * Expr.t
    | For of
        { init   : Expr.t option
        ; cond   : Expr.t option
        ; update : Expr.t option
        ; body   : t
        }
end
and Compound_stm : S_compound_stm
  with type stm := Stm.t = struct
  type t =
    { decls : Decl.t list
    ; stms  : Stm.t list
    }
  ;;
end

module Function_def = struct
  type t =
    { decl_specs : Decl_spec.t list
    ; signature  : Declarator.t
    ; decls      : Decl.t list
    ; body       : Compound_stm.t
    }
  ;;
end

module External_decl = struct
  type t =
    | Fun  of Function_def.t
    | Decl of Decl.t
  ;;
end

module Translation_unit = struct
  type t = External_decl.t list
end
