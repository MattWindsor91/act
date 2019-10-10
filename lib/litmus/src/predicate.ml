(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Core_kernel (* not Base; for extended quickcheck *)

module Id = Act_common.Litmus_id
module Tx = Travesty_base_exts

module Element = struct
  type 'const t = Bool of bool | Eq of Id.t * 'const
  [@@deriving sexp, compare, equal, quickcheck, variants]

  let ( ==? ) = eq

  let pp (f : Formatter.t) (e : 'const t) ~(pp_const : 'const Fmt.t) : unit
      =
    match e with
    | Bool true ->
        Fmt.pf f "true"
    | Bool false ->
        Fmt.pf f "false"
    | Eq (i, c) ->
        Fmt.pf f "%a@ ==@ %a" Id.pp i pp_const c

  module BT :
    Travesty.Bi_traversable_types.S1_right
      with type 'const t := 'const t
       and type left = Id.t = Travesty.Bi_traversable.Make1_right (struct
    type nonrec 'const t = 'const t

    type left = Id.t

    module On_monad (M : Monad.S) = struct
      let bi_map_m (t : 'a t) ~(left : Id.t -> Id.t M.t)
          ~(right : 'a -> 'b M.t) : 'b t M.t =
        match t with
        | Bool k ->
            M.return (Bool k)
        | Eq (id, c) ->
            M.Let_syntax.(
              let%map id' = left id and c' = right c in
              Eq (id', c'))
    end
  end)

  include BT

  (* TODO(@MattWindsor91): this is yet another pattern that needs putting
     into Travesty *)
  module On_c_identifiers :
    Travesty.Bi_traversable_types.S1_right
      with type 'const t = 'const t
       and type left = Act_common.C_id.t =
  Travesty.Bi_traversable.Make1_right (struct
    type nonrec 'const t = 'const t

    type left = Act_common.C_id.t

    module On_monad (M : Monad.S) = struct
      module Lid_cid = Act_common.Litmus_id.On_c_identifiers.On_monad (M)
      module B = On_monad (M)

      let bi_map_m (t : 'a t)
          ~(left : Act_common.C_id.t -> Act_common.C_id.t M.t)
          ~(right : 'a -> 'b M.t) : 'b t M.t =
        B.bi_map_m ~left:(Lid_cid.map_m ~f:left) ~right t
    end
  end)
end

module Bop = struct
  type t = Or | And
  [@@deriving sexp, compare, equal, variants, quickcheck]

  let to_string : t -> string = function Or -> "\\/" | And -> "/\\"

  let pp : t Fmt.t = Fmt.of_to_string to_string
end

type 'const t =
  | Bop of Bop.t * 'const t * 'const t
  | Elt of 'const Element.t
[@@deriving sexp, compare, equal, variants]

let or_ (l : 'const t) (r : 'const t) : 'const t = bop Or l r

let and_ (l : 'const t) (r : 'const t) : 'const t = bop And l r

let bool (b : bool) : 'const t = elt (Element.bool b)

let eq (k : Act_common.Litmus_id.t) (v : 'const) : 'const t =
  elt (Element.eq k v)

let reduce (x : 'const t) ~(elt : 'const Element.t -> 'a)
    ~(bop : Bop.t -> 'a -> 'a -> 'a) : 'a =
  let rec mu = function
    | Bop (o, l, r) ->
        bop o (mu l) (mu r)
    | Elt e ->
        elt e
  in
  mu x

let optimising_or (l : 'const t) (r : 'const t) : 'const t =
  match (l, r) with
  | Elt (Bool true), _ | _, Elt (Bool true) ->
      bool true
  | Elt (Bool false), x | x, Elt (Bool false) ->
      x
  | Bop (Or, x, y), z ->
      or_ x (or_ y z)
  | _ ->
      or_ l r

let optimising_or_seq (xs : 'const t Sequence.t) : 'const t =
  Sequence.fold xs ~init:(bool false) ~f:optimising_or

let optimising_and (l : 'const t) (r : 'const t) : 'const t =
  match (l, r) with
  | Elt (Bool false), _ | _, Elt (Bool false) ->
      bool false
  | Elt (Bool true), x | x, Elt (Bool true) ->
      x
  | Bop (And, x, y), z ->
      and_ x (and_ y z)
  | _ ->
      and_ l r

let optimising_and_seq (xs : 'const t Sequence.t) : 'const t =
  Sequence.fold xs ~init:(bool true) ~f:optimising_and

module Infix = struct
  let ( || ) (l : 'const t) (r : 'const t) : 'const t = or_ l r

  let ( ||+ ) (l : 'const t) (r : 'const t) : 'const t = optimising_or l r

  let ( && ) (l : 'const t) (r : 'const t) : 'const t = and_ l r

  let ( &&+ ) (l : 'const t) (r : 'const t) : 'const t = optimising_and l r

  let ( ==? ) (k : Act_common.Litmus_id.t) (v : 'const) : 'const t =
    elt (Element.eq k v)
end

module BT :
  Travesty.Bi_traversable_types.S1_right
    with type 'const t := 'const t
     and type left = Id.t = Travesty.Bi_traversable.Make1_right (struct
  type nonrec 'const t = 'const t

  type left = Id.t

  module On_monad (M : Monad.S) = struct
    module Pe = Element.On_monad (M)

    let rec bi_map_m (t : 'a t) ~(left : Id.t -> Id.t M.t)
        ~(right : 'a -> 'b M.t) : 'b t M.t =
      M.Let_syntax.(
        match t with
        | Bop (op, l, r) ->
            let%map l' = bi_map_m ~left ~right l
            and r' = bi_map_m ~left ~right r in
            Bop (op, l', r')
        | Elt x ->
            let%map x' = Pe.bi_map_m ~left ~right x in
            Elt x')
  end
end)

include BT

module On_c_identifiers :
  Travesty.Bi_traversable_types.S1_right
    with type 'const t = 'const t
     and type left = Act_common.C_id.t =
Travesty.Bi_traversable.Make1_right (struct
  type nonrec 'const t = 'const t

  type left = Act_common.C_id.t

  module On_monad (M : Monad.S) = struct
    module Lid_cid = Act_common.Litmus_id.On_c_identifiers.On_monad (M)
    module B = On_monad (M)

    let bi_map_m (t : 'a t)
        ~(left : Act_common.C_id.t -> Act_common.C_id.t M.t)
        ~(right : 'a -> 'b M.t) : 'b t M.t =
      B.bi_map_m ~left:(Lid_cid.map_m ~f:left) ~right t
  end
end)

module Q : Quickcheck.S1 with type 'const t := 'const t = struct
  module G = Quickcheck.Generator
  module O = Quickcheck.Observer
  module S = Quickcheck.Shrinker

  let anonymise = function Bop (o, l, r) -> `A (o, l, r) | Elt x -> `B x

  let deanonymise = function `A (o, l, r) -> Bop (o, l, r) | `B x -> Elt x

  let quickcheck_generator (elt : 'const G.t) : 'const t G.t =
    G.recursive_union
      [ G.map
          ~f:(fun x -> Elt x)
          [%quickcheck.generator: [%custom elt] Element.t] ]
      ~f:(fun mu ->
        [ G.map
            ~f:(fun (o, l, r) -> Bop (o, l, r))
            [%quickcheck.generator: Bop.t * [%custom mu] * [%custom mu]] ])

  let quickcheck_observer (elt : 'const O.t) : 'const t O.t =
    O.fixed_point (fun mu ->
        O.unmap ~f:anonymise
          [%quickcheck.observer:
            [ `A of Bop.t * [%custom mu] * [%custom mu]
            | `B of [%custom elt] Element.t ]])

  let quickcheck_shrinker (elt : 'const S.t) : 'const t S.t =
    S.fixed_point (fun mu ->
        S.map ~f:deanonymise ~f_inverse:anonymise
          [%quickcheck.shrinker:
            [ `A of Bop.t * [%custom mu] * [%custom mu]
            | `B of [%custom elt] Element.t ]])
end

include Q

let left_needs_brackets (o : Bop.t) : 'const t -> bool = function
  | Bop (o', _, _) ->
      not (Bop.equal o o')
  | Elt _ ->
      false

let right_needs_brackets (_o : Bop.t) : 'const t -> bool = function
  | Bop (_o', _, _) ->
      true
  | Elt _ ->
      false

let rec pp (f : Formatter.t) (pred : 'const t) ~(pp_const : 'const Fmt.t) :
    unit =
  let elt f = Element.pp f ~pp_const in
  let mu = pp ~pp_const in
  match pred with
  | Bop (o, l, r) ->
      let pp_l = if left_needs_brackets o l then Fmt.parens mu else mu in
      let pp_r = if right_needs_brackets o r then Fmt.parens mu else mu in
      Fmt.(pf f "%a@ %a@ %a" pp_l l Bop.pp o pp_r r)
  | Elt e ->
      elt f e