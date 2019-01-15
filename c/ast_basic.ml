(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor (parts (c) 2010-2018 Institut
   National de Recherche en Informatique et en Automatique, Jade
   Alglave, and Luc Maranget)

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation
   files (the "Software"), to deal in the Software without
   restriction, including without limitation the rights to use, copy,
   modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.

   This file derives from the Herd7 project
   (https://github.com/herd/herdtools7); its original attribution and
   copyright notice follow. *)

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

open Core_kernel

include Ast_basic_intf

module Operators = struct
  module Assign = struct
    type t =
      [ `Assign     (*   = *)
      | `Assign_mul (*  *= *)
      | `Assign_div (*  /= *)
      | `Assign_mod (*  %= *)
      | `Assign_add (*  += *)
      | `Assign_sub (*  -= *)
      | `Assign_shl (* <<= *)
      | `Assign_shr (* >>= *)
      | `Assign_and (*  &= *)
      | `Assign_xor (*  ^= *)
      | `Assign_or  (*  |= *)
      ]
    [@@deriving sexp]
    ;;

    let to_string : t -> string = function
      | `Assign     ->   "="
      | `Assign_mul ->  "*="
      | `Assign_div ->  "/="
      | `Assign_mod ->  "%="
      | `Assign_add ->  "+="
      | `Assign_sub ->  "-="
      | `Assign_shl -> "<<="
      | `Assign_shr -> ">>="
      | `Assign_and ->  "&="
      | `Assign_xor ->  "^="
      | `Assign_or  ->  "|="
    ;;

    let pp : t Fmt.t = Fmt.of_to_string to_string
  end

  module Bin = struct
    type t =
      [ Assign.t
      | `Comma (* ,  *)
      | `Mul   (* *  *)
      | `Div   (* /  *)
      | `Mod   (* %  *)
      | `Add   (* +  *)
      | `Sub   (* -  *)
      | `Shl   (* << *)
      | `Shr   (* >> *)
      | `And   (* &  *)
      | `Xor   (* ^  *)
      | `Or    (* |  *)
      | `Land  (* && *)
      | `Lor   (* || *)
      | `Lt    (* <  *)
      | `Le    (* <= *)
      | `Eq    (* == *)
      | `Ge    (* >= *)
      | `Gt    (* >  *)
      | `Ne    (* != *)
      ]
    [@@deriving sexp]
    ;;

    let to_string : t -> string = function
      | #Assign.t as a -> Assign.to_string a
      | `Comma -> ","
      | `Mul   -> "*"
      | `Div   -> "/"
      | `Mod   -> "%"
      | `Add   -> "+"
      | `Sub   -> "-"
      | `Shl   -> "<<"
      | `Shr   -> ">>"
      | `And   -> "&"
      | `Xor   -> "^"
      | `Or    -> "|"
      | `Land  -> "&&"
      | `Lor   -> "||"
      | `Lt    -> "<"
      | `Le    -> "<="
      | `Eq    -> "=="
      | `Ge    -> ">="
      | `Gt    -> ">"
      | `Ne    -> "!="
    ;;

    let pp : t Fmt.t = Fmt.of_to_string to_string
  end

  module Pre = struct
    type t =
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
    [@@deriving sexp]
    ;;

    let to_string : t -> string = function
      | `Inc        -> "++"
      | `Dec        -> "--"
      | `Sizeof_val -> "sizeof"
      | `Ref        -> "&"
      | `Deref      -> "*"
      | `Add        -> "+"
      | `Sub        -> "-"
      | `Not        -> "~"
      | `Lnot       -> "!"
    ;;

    let pp : t Fmt.t = Fmt.of_to_string to_string
  end

  module Post = struct
    type t =
      [ `Inc (* ++ *)
      | `Dec (* -- *)
      ]
    [@@deriving sexp]
    ;;

    let to_string : t -> string = function
      | `Inc -> "++"
      | `Dec -> "--"
    ;;

    let pp : t Fmt.t = Fmt.of_to_string to_string
  end
end

module Type_qual = struct
  module M = struct
    type t =
      [ `Const
      | `Volatile
      ]
    [@@deriving sexp, enum]
    ;;

    let table : (t, string) List.Assoc.t =
      [ `Const   , "const"
      ; `Volatile, "volatile"
      ]
    ;;
  end

  include M
  include Utils.Enum.Extend_table (M)
end

module Prim_type = struct
  module M = struct
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
    [@@deriving sexp, enum]
    ;;

    let table : (t, string) List.Assoc.t =
      [ `Void    , "void"
      ; `Char    , "char"
      ; `Short   , "short"
      ; `Int     , "int"
      ; `Long    , "long"
      ; `Float   , "float"
      ; `Double  , "double"
      ; `Signed  , "signed"
      ; `Unsigned, "unsigned"
      ]
    ;;
  end

  include M
  include Utils.Enum.Extend_table (M)
end

module Storage_class_spec = struct
  module M = struct
    type t =
      [ `Auto
      | `Register
      | `Static
      | `Extern
      | `Typedef
      ]
    [@@deriving sexp, enum]
    ;;

    let table : (t, string) List.Assoc.t =
      [ `Auto    , "auto"
      ; `Register, "register"
      ; `Static  , "static"
      ; `Extern  , "extern"
      ; `Typedef , "typedef"
      ]
    ;;
  end

  include M
  include Utils.Enum.Extend_table (M)
end

module Array = struct
  type ('a, 'i) t = { array : 'a; index : 'i } [@@deriving sexp]

  let pp ppa ppi =
    Fmt.(
      using (fun { array; index } -> (array, index))
        (append ppa (brackets ppi))
    )
  ;;

  module type S = sig
    type arr (** Type of arrays *)
    type idx (** Type of indices *)

    type nonrec t = (arr, idx) t [@@deriving sexp]

    include Ast_node with type t := t
  end

  module Make (A : Ast_node) (I : Ast_node) : S
    with type arr := A.t and type idx := I.t = struct

    type nonrec t = (A.t, I.t) t
    let t_of_sexp = t_of_sexp A.t_of_sexp I.t_of_sexp
    let sexp_of_t = sexp_of_t A.sexp_of_t I.sexp_of_t
    let pp = pp A.pp I.pp
  end
end

module Constant = struct
  type t =
    | Char    of char
    | Float   of float
    | Integer of int
  [@@deriving sexp, variants, eq, compare]
  ;;

  (* TODO(@MattWindsor91): escaping *)
  let escape_char = Char.to_string

  let pp_char =
    Fmt.(quote ~mark:"'" (using escape_char string))

  let pp f = function
    | Char c -> pp_char f c
    | Float d -> Fmt.float f d
    | Integer i -> Fmt.int f i

  let anonymise = function
    | Char c    -> `A c
    | Float f   -> `B f
    | Integer i -> `C i
  ;;

  let deanonymise = function
    | `A c -> Char c
    | `B f -> Float f
    | `C i -> Integer i
  ;;

  let gen : t Quickcheck.Generator.t =
    let module G = Quickcheck.Generator in
    G.map ~f:deanonymise (G.variant3 Char.gen Float.gen Int.gen)
  ;;

  let obs : t Quickcheck.Observer.t =
    let module O = Quickcheck.Observer in
    O.unmap (O.variant3 Char.obs Float.obs Int.obs)
      ~f:anonymise
  ;;

  let shrinker : t Quickcheck.Shrinker.t =
    let module S = Quickcheck.Shrinker in
    S.map ~f:deanonymise ~f_inverse:anonymise
      (S.variant3 Char.shrinker Float.shrinker Int.shrinker)
end

module Identifier = struct
  type t = string [@@deriving sexp, eq]

  let identifier = Fn.id
  let pp = Fmt.string

  let gen : t Quickcheck.Generator.t =
    let module G = Quickcheck.Generator in
    let open G.Let_syntax in
    let initial =
      G.union
         [ Char.gen_alpha
         ; G.return '_'
         ]
    in
    let%bind chr = initial in
    let%map rest =
      String.gen'
        (G.union
           [ Char.gen_alphanum
           ; G.return '_'
           ]
        )
    in String.of_char chr ^ rest

  let validate_initial_char : char Validate.check =
    Validate.booltest
      (Travesty.T_fn.disj Char.is_alpha (Char.equal '_'))
      ~if_false:"Invalid initial character."
  ;;

  let validate_char : char Validate.check =
    Validate.booltest
      (Travesty.T_fn.disj Char.is_alphanum (Char.equal '_'))
      ~if_false:"Invalid character."
  ;;

  let validate : t Validate.check =
    fun id ->
      match String.to_list id with
      | [] -> Validate.fail_s
                [%message "Identifiers can't be empty"
                  ~id]
      | c :: cs ->
        Validate.of_list
          (validate_initial_char c :: List.map ~f:validate_char cs)
  ;;

  let is_valid (id : t) : bool =
    Or_error.is_ok (Validate.result (validate id))
  ;;

  let obs : t Quickcheck.Observer.t = String.obs

  let shrinker : t Quickcheck.Shrinker.t =
    Quickcheck.Shrinker.create
      (fun ident ->
         ident
         |> Quickcheck.Shrinker.shrink String.shrinker
         |> Sequence.filter ~f:is_valid
      )
  ;;
end

module Pointer : Ast_node with type t = (Type_qual.t list) list = struct
  type t = (Type_qual.t list) list
  [@@deriving sexp]

  let pp : t Fmt.t =
    Fmt.(list ~sep:sp (prefix (unit "*") (list ~sep:sp Type_qual.pp)))
end