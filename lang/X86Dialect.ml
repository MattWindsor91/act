(*
This file is part of 'act'.

Copyright (c) 2018 by Matt Windsor
   (parts (c) 2010-2018 Institut National de Recherche en Informatique et
	                en Automatique, Jade Alglave, and Luc Maranget)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

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

open Core
open Utils

type t =
  | Att
  | Intel
  | Herd7

module Map =
  StringTable.Make
    (struct
      type nonrec t = t
      let table =
        [ Att  , "AT&T"
        ; Intel, "Intel"
        ; Herd7, "Herd7"
        ]
    end)

let sexp_of_t syn =
  syn |> Map.to_string_exn |> Sexp.Atom

let t_of_sexp =
  function
  | Sexp.Atom a as s ->
     begin
       match Map.of_string a with
       | Some v -> v
       | None -> raise (Sexp.Of_sexp_error (failwith "expected x86 dialect name", s))
     end
  | s -> raise (Sexp.Of_sexp_error (failwith "expected x86 dialect, not a list", s))

let pp f syn =
  Format.pp_print_string f (Option.value ~default:"??" (Map.to_string syn))

type operand_order =
  | SrcDst
  | DstSrc

let operand_order_of = function
  | Att -> SrcDst
  | Intel
    | Herd7 -> DstSrc

let has_size_suffix_in = function
  | Att
    (* Surprisingly enough, herd7 syntax uses AT&T suffixes
       (for 'mov', at least!). *)
    | Herd7 -> true
  | Intel -> false


module type HasDialect =
  sig
    val dialect : t
  end

module type Traits =
  sig
    include HasDialect

    val operand_order : operand_order
    val has_size_suffix : bool

    val of_src_dst : 'o -> 'o -> 'o list
    val to_src_dst : 'o list -> ('o * 'o) option
    val bind_src_dst : f:('o -> 'o -> ('o * 'o) option) -> 'o list -> ('o list) option
    val map_src_dst : f:('o -> 'o -> ('o * 'o)) -> 'o list -> ('o list) option
  end

(** [MakeTraits] wraps the trait functions in a module, and adds some
    convenience methods. *)
module MakeTraits (N : HasDialect) =
  struct
    include N

    let operand_order = operand_order_of N.dialect
    let has_size_suffix = has_size_suffix_in N.dialect

    let of_src_dst src dst =
      match operand_order with
      | SrcDst -> [src; dst]
      | DstSrc -> [dst; src]

    let to_src_dst =
      function
      | [o1; o2] ->
         (match operand_order with
          | SrcDst -> Some (o1, o2)
          | DstSrc -> Some (o2, o1))
      | _ -> None

    open Option

    let bind_src_dst ~f xs =
      to_src_dst xs
      >>= (fun (s, d) -> f s d)
      >>| Tuple2.uncurry of_src_dst

    let map_src_dst ~f = bind_src_dst ~f:(fun s d -> Some (f s d))
  end

module ATTTraits = MakeTraits (struct let dialect = Att end)
module IntelTraits = MakeTraits (struct let dialect = Intel end)
module Herd7Traits = MakeTraits (struct let dialect = Herd7 end)