(* This file is part of c4f.

   Copyright (c) 2018-2021 C4 Project

   c4t itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   Parts of c4t are based on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

type 'e t =
  { obj: Address.t
  ; desired: 'e
  ; mo: Mem_order.t [@quickcheck.generator Mem_order.gen_rmw] }
[@@deriving sexp, fields, make, compare, equal, quickcheck]

module Base_map (Ap : Applicative.S) = struct
  let bmap (x : 'a t) ~(obj : Address.t -> Address.t Ap.t)
      ~(desired : 'a -> 'b Ap.t) ~(mo : Mem_order.t -> Mem_order.t Ap.t) :
      'b t Ap.t =
    Ap.(
      let m obj desired mo = make ~obj ~desired ~mo in
      return m <*> obj x.obj <*> desired x.desired <*> mo x.mo)
end

module On_expressions : Travesty.Traversable_types.S1 with type 'e t = 'e t =
Travesty.Traversable.Make1 (struct
  type nonrec 'e t = 'e t

  module On (M : Applicative.S) = struct
    module B = Base_map (M)

    let map_m (x : 'a t) ~(f : 'a -> 'b M.t) : 'b t M.t =
      B.bmap x ~obj:M.return ~desired:f ~mo:M.return
  end
end)

module Type_check (Env : Env_types.S) = struct
  type nonrec t = Type.t t

  module Ad = Address.Type_check (Env)

  let check_obj_desired ~(obj : Type.t) ~(desired : Type.t) :
      Type.t Or_error.t =
    Or_error.(
      tag
        Type.(desired |> to_non_atomic >>= deref >>= check obj)
        ~tag:
          "'obj' type must be same as pointer to atomic form of 'desired' \
           type")

  let type_of (c : t) : Type.t Or_error.t =
    Or_error.Let_syntax.(
      let%bind obj = Ad.type_of (obj c) in
      check_obj_desired ~obj ~desired:(desired c))
end
