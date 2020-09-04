(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
open Base_quickcheck

open struct
  module A = Accessor_base
end

module Acc = struct
  type t = Bool of bool | Int of int
  [@@deriving compare, equal, sexp, quickcheck, accessors]

  let true_ = [%accessor A.(bool @> A.Bool.true_)]
  let false_ = [%accessor A.(bool @> A.Bool.false_)]

  let int_zero =
    [%accessor
    A.variant ~match_:(function
     | 0 -> First ()
     | n -> Second n
    )
    ~construct:(fun () -> 0)]

  let zero = [%accessor A.(int @> int_zero)]
end

include Acc
include Comparable.Make (Acc)

let bool = A.construct bool
let int = A.construct int
let truth : t = Bool true

let falsehood : t = Bool false

let type_of : t -> Type.t = function
  | Bool _ ->
      Type.bool ()
  | Int _ ->
      Type.int ()

let zero_of_type (t : Type.t) : t =
  if
    Type.(
      is_pointer t
      || Prim.eq Accessor.(Access.basic_type @> Basic.Access.prim) t ~to_:Int)
  then Int 0
  else Bool false

let is_bool : t -> bool = function Bool _ -> true | Int _ -> false

let is_int : t -> bool = function Int _ -> true | Bool _ -> false

let reduce (k : t) ~(int : int -> 'a) ~(bool : bool -> 'a) : 'a =
  match k with Bool b -> bool b | Int i -> int i

let as_bool : t -> bool Or_error.t =
  Fn.compose
    (Result.of_option ~error:(Error.of_string "expected bool; got int"))
    (A.get_option Acc.bool)

let as_int : t -> int Or_error.t =
  Fn.compose
    (Result.of_option ~error:(Error.of_string "expected int; got bool"))
    (A.get_option Acc.int)

let pp (f : Formatter.t) : t -> unit =
  reduce ~int:(Fmt.int f) ~bool:(Fmt.bool f)

let yojson_of_t : t -> Yojson.Safe.t = function
  | Bool d ->
      `Bool d
  | Int i ->
      `Int i

let t_of_yojson' (json : Yojson.Safe.t) : (t, string) Result.t =
  let js = [json] in
  Yojson.Safe.Util.(
    match filter_int js with
    | [i] ->
        Result.return (int i)
    | _ -> (
      match filter_bool js with
      | [b] ->
          Result.return (bool b)
      | _ ->
          Result.fail "malformed JSON encoding of C literal" ))

let t_of_yojson (json : Yojson.Safe.t) : t =
  Result.ok_or_failwith (t_of_yojson' json)

let gen_int32_as_int : int Generator.t =
  Generator.map [%quickcheck.generator: int32] ~f:(fun x ->
      Option.value ~default:0 (Int.of_int32 x))

let gen_int32 : t Generator.t = Generator.map ~f:int gen_int32_as_int

let gen_bool : t Generator.t =
  Generator.map ~f:bool [%quickcheck.generator: bool]

let quickcheck_generator : t Generator.t =
  Base_quickcheck.Generator.union [gen_int32; gen_bool]

let convert (x : t) ~(to_ : Type.Prim.t) : t Or_error.t =
  (* The Or_error wrapper is future-proofing for if we have unconvertable
     constants later on. *)
  match (x, to_) with
  | Int _, Int | Bool _, Bool ->
      Ok x
  (* Draft C11, 6.3.1.2 - sort of. We represent _Bool 0 as false, and _Bool 1
     as true. *)
  | Int 0, Bool ->
      Ok (Bool false)
  | Int _, Bool ->
      Ok (Bool true)
  | Bool false, Int ->
      Ok (Int 0)
  | Bool true, Int ->
      Ok (Int 1)

let convert_as_bool : t -> bool Or_error.t =
  Travesty_base_exts.Or_error.(convert ~to_:Bool >=> as_bool)

let convert_as_int : t -> int Or_error.t =
  Travesty_base_exts.Or_error.(convert ~to_:Int >=> as_int)
