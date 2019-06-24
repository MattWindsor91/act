(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
module Tx = Travesty_base_exts
module Ac = Act_common

type 'const t =
  { locations: Ac.C_id.t list option
  ; init: (Ac.C_id.t * 'const) list
  ; postcondition: 'const Ast_base.Postcondition.t option }
[@@deriving fields, make, equal, sexp]

let empty (type k) : k t = {locations= None; init= []; postcondition= None}

module BT :
  Travesty.Bi_traversable.S1_right
  with type 'const t := 'const t
   and type left = Act_common.C_id.t =
Travesty.Bi_traversable.Make1_right (struct
  type nonrec 'const t = 'const t

  type left = Act_common.C_id.t

  module On_monad (M : Monad.S) = struct
    module MA = Travesty_base_exts.Alist.On_monad (M)
    module PostO =
      Travesty.Bi_traversable.Chain_Bi1_right_Traverse1
        (Ast_base.Postcondition.On_c_identifiers)
        (Travesty_base_exts.Option)
    module MP = PostO.On_monad (M)
    module Mx = Travesty.Monad_exts.Extend (M)

    let bi_map_m (type a b) (aux : a t) ~(left : Ac.C_id.t -> Ac.C_id.t M.t)
        ~(right : a -> b M.t) : b t M.t =
      let locations = locations aux in
      M.Let_syntax.(
        let%map init = MA.bi_map_m (init aux) ~left ~right
        and postcondition = MP.bi_map_m (postcondition aux) ~left ~right in
        make ~init ?locations ?postcondition ())
  end
end)

include BT

(* We can't easily derive yojson for the whole thing, since the
   postcondition serialisation depends on being able to pretty-print and
   parse the postcondition rather than recursively serialising it. *)

module Json (Const : sig
  type t

  include Pretty_printer.S with type t := t

  include Plumbing.Loadable_types.Jsonable with type t := t

  val parse_post_string : string -> t Ast_base.Postcondition.t Or_error.t
end) : Plumbing.Loadable_types.Jsonable with type t = Const.t t = struct
  type nonrec t = Const.t t

  let opt (foo : 'a option) ~(f : 'a -> Yojson.Safe.t) : Yojson.Safe.t =
    Option.value_map foo ~f ~default:`Null

  let postcondition_to_json (pc : Const.t Ast_base.Postcondition.t) :
      Yojson.Safe.t =
    `String
      (Fmt.strf "@[<h>%a@]" (Pp.Generic.pp_post ~pp_const:Const.pp) pc)

  let to_yojson (aux : t) : Yojson.Safe.t =
    (* Need to open Caml because some of to_yojson's code depends on the
       stdlib versions of some things Base shadows. *)
    `Assoc
      Caml.
        [ ("locations", [%to_yojson: Ac.C_id.t list option] (locations aux))
        ; ("init", [%to_yojson: Const.t Ac.C_id.Alist.t] (init aux))
        ; ("postcondition", opt ~f:postcondition_to_json (postcondition aux))
        ]

  module U = Yojson.Safe.Util

  let postcondition_of_json (json : Yojson.Safe.t) :
      (Const.t Ast_base.Postcondition.t option, string) Result.t =
    let result =
      Or_error.Let_syntax.(
        let%bind post_str =
          Or_error.try_with (fun () -> U.to_string_option json)
        in
        Tx.Option.With_errors.map_m ~f:Const.parse_post_string post_str)
    in
    Result.map_error ~f:Error.to_string_hum result

  let of_yojson (json : Yojson.Safe.t) : (t, string) Result.t =
    Result.Let_syntax.(
      let%bind locations =
        [%of_yojson: Ac.C_id.t list option] (U.member "locations" json)
      in
      let%bind init =
        [%of_yojson: Const.t Ac.C_id.Alist.t] (U.member "init" json)
      in
      let%map postcondition =
        postcondition_of_json (U.member "postcondition" json)
      in
      make ?locations ~init ?postcondition ())

  let of_yojson_exn (json : Yojson.Safe.t) : t =
    Result.ok_or_failwith (of_yojson json)
end