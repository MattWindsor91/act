(* This file is part of 'act'.

   Copyright (c) 2018, 2019 by Matt Windsor

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
   SOFTWARE. *)

open Core_kernel
open Utils

module Address = Mini_address
module Constant = Ast_basic.Constant
module Env = Mini_env
module Identifier = Ast_basic.Identifier
module Lvalue = Mini_lvalue
module Type = Mini_type

module Atomic_load = struct
  type t =
    { src : Address.t
    ; mo  : Mem_order.t
    }
  [@@deriving sexp, fields, make]
  ;;

  let to_tuple ({ src; mo } : t) : Address.t * Mem_order.t = ( src, mo )
  let of_tuple (( src, mo ) : Address.t * Mem_order.t) : t = { src; mo }

  module Base_map (M : Monad.S) = struct
    module F = Travesty.Traversable.Helpers (M)
    let bmap (store : t)
        ~(src : Address.t    F.traversal)
        ~(mo  : Mem_order.t  F.traversal)
      : t M.t =
      Fields.fold
        ~init:(M.return store)
        ~src:(F.proc_field src)
        ~mo:(F.proc_field mo)
    ;;
  end

  module On_addresses : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Address.t =
    Travesty.Traversable.Make_container0 (struct
      type nonrec t = t
      module Elt = Address

      module On_monad (M : Monad.S) = struct
        module B = Base_map (M)
        let map_m x ~f = B.bmap x ~src:f ~mo:(M.return)
      end
    end)

  module On_lvalues : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Lvalue.t =
    Travesty.Traversable.Chain0
      (struct
        type nonrec t = t
        include On_addresses
      end)
      (Address.On_lvalues)
  ;;

  module Type_check (E : Env.S) = struct
    module A = Address.Type_check (E)

    let type_of (ld : t) : Type.t Or_error.t =
      let open Or_error.Let_syntax in
      let%bind a_ptr = A.type_of (src ld) in
      let%bind a     = Type.deref a_ptr in
      Type.to_non_atomic a
    ;;
  end

  let%expect_test "type_of: atomic_int* -> int" =
    let (module E) = Lazy.force Env.test_env_mod in
    let module Ty  = Type_check (E) in
    let src =
      Address.lvalue (Lvalue.variable (C_identifier.of_string "bar"))
    in
    let ld =  make ~src ~mo:Mem_order.Seq_cst in
    Sexp.output_hum stdout [%sexp (Ty.type_of ld : Type.t Or_error.t)];
    [%expect {| (Ok (Normal int)) |}]
  ;;

  module Quickcheck_generic
      (A : Quickcheckable.S with type t := Address.t)
    : Quickcheckable.S with type t := t = struct
    module Gen = Core_kernel.Quickcheck.Generator
    module Obs = Core_kernel.Quickcheck.Observer
    module Snk = Core_kernel.Quickcheck.Shrinker

    let gen : t Gen.t =
      Gen.(map (tuple2 A.gen Mem_order.gen_load) ~f:of_tuple)
    ;;

    let obs : t Obs.t =
      Obs.(unmap (tuple2 A.obs Mem_order.obs) ~f:to_tuple)
    ;;

    let shrinker : t Snk.t =
      Snk.(map (tuple2 A.shrinker Mem_order.shrinker)
             ~f:of_tuple ~f_inverse:to_tuple
          )
    ;;
  end
  include Quickcheck_generic (Address)

  module Quickcheck_atomic_ints (E : Env.S)
    : Quickcheckable.S with type t := t =
    Quickcheck_generic (Address.Quickcheck_atomic_int_pointers (E))
  ;;

  let variable_of (ld : t) : C_identifier.t =
    Address.variable_of (src ld)
  ;;

  let variable_in_env (ld : t) ~(env : _ C_identifier.Map.t) : bool =
    Address.variable_in_env (src ld) ~env
  ;;

  let%test_unit
    "Quickcheck_atomic_ints: liveness" =
    let (module E) = Lazy.force Env.test_env_mod in
    let module Q = Quickcheck_atomic_ints (E) in
    Quickcheck.test_can_generate Q.gen
      ~sexp_of:[%sexp_of: t]
      ~f:(variable_in_env ~env:E.env)
  ;;

  let%test_unit
    "Quickcheck_atomic_ints: generated underlying variables in environment" =
    let (module E) = Lazy.force Env.test_env_mod in
    let module Q = Quickcheck_atomic_ints (E) in
    Quickcheck.test Q.gen
      ~sexp_of:[%sexp_of: t]
      ~shrinker:Q.shrinker
      ~f:([%test_pred: t] ~here:[[%here]] (variable_in_env ~env:E.env))
  ;;
end

type t =
  | Constant    of Constant.t
  | Lvalue      of Lvalue.t
  | Atomic_load of Atomic_load.t
  | Eq          of t * t
[@@deriving sexp, variants]
;;

let reduce (expr : t)
    ~(constant    : Constant.t -> 'a)
    ~(lvalue      : Lvalue.t   -> 'a)
    ~(atomic_load : Atomic_load.t -> 'a)
    ~(eq          : 'a -> 'a   -> 'a) : 'a =
  let rec mu = function
    | Constant    k      -> constant k
    | Lvalue      l      -> lvalue l
    | Atomic_load ld     -> atomic_load ld
    | Eq          (x, y) -> eq (mu x) (mu y)
  in mu expr
;;

let anonymise = function
  | Constant    k      -> `A k
  | Lvalue      l      -> `B l
  | Eq          (x, y) -> `C ((x, y))
  | Atomic_load ld     -> `D ld
;;

module On_addresses
  : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Address.t =
  Travesty.Traversable.Make_container0 (struct
    type nonrec t = t
    module Elt = Address

    module On_monad (M : Monad.S) = struct
      module F = Travesty.Traversable.Helpers (M)
      module A = Atomic_load.On_addresses.On_monad (M)

      let rec map_m x ~f =
        Variants.map x
          ~constant:(F.proc_variant1 M.return)
          ~lvalue:(F.proc_variant1 M.return)
          ~eq:(F.proc_variant2
                 (fun (l, r) ->
                    let open M.Let_syntax in
                    let%bind l' = map_m l ~f in
                    let%map  r' = map_m r ~f in
                    (l', r')))
          ~atomic_load:(F.proc_variant1 (A.map_m ~f))
    end
  end)

module On_lvalues
  : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Lvalue.t =
  Travesty.Traversable.Make_container0 (struct
    type nonrec t = t
    module Elt = Lvalue

    module On_monad (M : Monad.S) = struct
      module A = Atomic_load.On_lvalues.On_monad (M)
      module F = Travesty.Traversable.Helpers (M)

      let rec map_m x ~f =
        Variants.map x
          ~constant:(F.proc_variant1 M.return)
          ~lvalue:(F.proc_variant1 f)
          ~eq:(F.proc_variant2
                 (fun (l, r) ->
                    let open M.Let_syntax in
                    let%bind l' = map_m l ~f in
                    let%map  r' = map_m r ~f in
                    (l', r')))
          ~atomic_load:(F.proc_variant1 (A.map_m ~f))
    end
  end)

module On_identifiers
  : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Identifier.t =
  Travesty.Traversable.Chain0
    (struct
      type nonrec t = t
      include On_lvalues
    end)
    (Lvalue.On_identifiers)

module Type_check (E : Env.S) = struct
  module Lv = Lvalue.Type_check (E)
  module Ld = Atomic_load.Type_check (E)

  let type_of_constant : Constant.t -> Type.t Or_error.t = function
    | Char    _ -> Or_error.unimplemented "char type"
    | Float   _ -> Or_error.unimplemented "float type"
    | Integer _ -> Or_error.return Type.(normal Basic.int)
  ;;

  let rec type_of : t -> Type.t Or_error.t = function
    | Constant    k      -> type_of_constant k
    | Lvalue      l      -> Lv.type_of l
    | Eq          (l, r) -> type_of_relational l r
    | Atomic_load ld     -> Ld.type_of ld
  and type_of_relational (l : t) (r : t) : Type.t Or_error.t =
    let open Or_error.Let_syntax in
    let%map _ = type_of l
    and     _ = type_of r
    in Type.(normal Basic.bool)
  ;;
end

module Quickcheck_int_values (E : Env.S)
  : Quickcheckable.S with type t := t = struct
  module Gen = Quickcheck.Generator
  module Obs = Quickcheck.Observer
  module Snk = Quickcheck.Shrinker

  (** Generates the terminal integer expressions. *)
  let base_generators : t Gen.t list =
    (* Use thunks and let-modules here to prevent accidentally
       evaluating a generator that can't possibly work---eg, an
       atomic load when we don't have any atomic variables. *)
    List.map ~f:Gen.of_fun
      (List.filter_opt
         [ Some (fun () -> Gen.map ~f:constant Constant.gen_int32_constant)
         ; Option.some_if
             (E.has_atomic_int_variables ())
             (fun () ->
                let module A = Atomic_load.Quickcheck_atomic_ints (E) in
                Gen.map ~f:atomic_load A.gen)
         ; Option.some_if
             (E.has_int_variables ())
             (fun () ->
                let module L = Lvalue.Quickcheck_int_values (E) in
                Gen.map ~f:lvalue L.gen)
         ]
      )

(*
    let recursive_generators (_mu : t Gen.t) : t Gen.t list =
      [] (* No useful recursive expression types yet. *)
    ;; *)

  let gen : t Gen.t =
    Gen.union base_generators (* ~f:recursive_generators *)
  ;;

  let obs : t Obs.t =
    Quickcheck.Observer.fixed_point
      (fun mu ->
         Obs.unmap ~f:anonymise
           (Obs.variant4
              Constant.obs
              Lvalue.obs
              (Obs.tuple2 mu mu)
              Atomic_load.obs
           )
      )
  ;;

  (* TODO(@MattWindsor91): implement this *)
  let shrinker : t Snk.t = Snk.empty ()
end

let test_int_values_liveness_on_mod (module E : Env.S) : unit =
  let module Ty = Type_check (E) in
  let module Q = Quickcheck_int_values (E) in
  Quickcheck.test_can_generate Q.gen
    ~sexp_of:[%sexp_of: t]
    ~f:(fun e ->
        Type.([%compare.equal: t Or_error.t]
                (Ty.type_of e)
                (Or_error.return (normal Basic.int))
             )
      )
;;

let test_int_values_distinctiveness_on_mod (module E : Env.S) : unit =
  let module Ty = Type_check (E) in
  let module Q = Quickcheck_int_values (E) in
  Quickcheck.test_distinct_values ~trials:20 ~distinct_values:5 Q.gen
    ~sexp_of:[%sexp_of: t]
    ~compare:[%compare: t]
;;

let%test_unit
  "Quickcheck_int_values: liveness" =
  test_int_values_liveness_on_mod (Lazy.force Env.test_env_mod)
;;

let%test_unit
  "Quickcheck_int_values: liveness (environment has only atomic_int*)" =
  test_int_values_liveness_on_mod (Lazy.force Env.test_env_atomic_ptrs_only_mod)
;;

let%test_unit
  "Quickcheck_int_values: liveness (environment is empty)" =
  test_int_values_liveness_on_mod (Lazy.force Env.empty_env_mod)
;;

let%test_unit
  "Quickcheck_int_values: distinctiveness" =
  test_int_values_distinctiveness_on_mod (Lazy.force Env.test_env_mod)
;;

let%test_unit
  "Quickcheck_int_values: distinctiveness (environment has only atomic_int*)" =
  test_int_values_distinctiveness_on_mod (Lazy.force Env.test_env_atomic_ptrs_only_mod)
;;

let%test_unit
  "Quickcheck_int_values: distinctiveness (environment is empty)" =
  test_int_values_distinctiveness_on_mod (Lazy.force Env.empty_env_mod)
;;

let%test_unit
  "Quickcheck_int_values: all expressions have 'int' type" =
  let (module E) = Lazy.force Env.test_env_mod in
  let module Ty = Type_check (E) in
  let module Q = Quickcheck_int_values (E) in
  Quickcheck.test Q.gen
    ~sexp_of:[%sexp_of: t]
    ~shrinker:Q.shrinker
    ~f:(fun e ->
        [%test_result: Type.t Or_error.t]
          (Ty.type_of e)
          ~here:[[%here]]
          ~equal:[%compare.equal: Type.t Or_error.t]
          ~expect:(Or_error.return Type.(normal Basic.int))
      )
;;

let%test_unit
  "Quickcheck_int_values: all referenced variables in environment" =
  let (module E) = Lazy.force Env.test_env_mod in
  let module Q = Quickcheck_int_values (E) in
  Quickcheck.test Q.gen
    ~sexp_of:[%sexp_of: t]
    ~shrinker:Q.shrinker
    ~f:([%test_pred: t]
          (On_identifiers.for_all ~f:(C_identifier.Map.mem E.env))
          ~here:[[%here]]
       )
;;
(*
  module Quickcheck_bools (E : Env.S)
    : Quickcheckable.S with type t := t = struct
    module G = Quickcheck.Generator
    module O = Quickcheck.Observer
    module S = Quickcheck.Shrinker

    let gen : t G.t =
      let open G.Let_syntax in
      Quickcheck.Generator.union
        [ gen_int_relational
        ; gen_const
        ]
  end *)
