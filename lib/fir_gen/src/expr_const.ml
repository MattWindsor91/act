(* The Automagic Compiler Tormentor

   Copyright (c) 2018, 2019, 2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
open Import

open struct
  type env = Fir.Env.t

  type t = Fir.Expression.t
end

(** [bop k operands] binary operations over [operands] that have any operand
    type, but result in [k]. *)
let bop (k : Fir.Constant.t) : Op.Operand_set.t -> t Q.Generator.t =
  (* TODO(@MattWindsor91): make sure the type is right. *)
  Op.bop (module Fir.Op.Binary) ~promote:Fn.id ~out:(Const k)

(** [arb_bop k kv_env ~gen_arb] generates binary operations of the form
    [x op x], [x op k2], or [k2 op x], where [x] is an arbitrary expression
    generated by [gen_arb], [k2] is a specific constant, and the resulting
    operation is known to produce [k]. *)
let arb_bop (k : Fir.Constant.t) (kv_env : env)
    ~(gen_arb : env -> t Q.Generator.t) : t Q.Generator.t =
  (* This is [kv_env] because it depends on the value not changing between
     reading the LHS and reading the LHS. *)
  Q.Generator.(
    Let_syntax.(
      let%bind size = size in
      let%bind p = with_size ~size:(size / 2) (gen_arb kv_env) in
      bop k (One p)))

(** [kv_bop k kv_env ~gen_load] generates binary operations of the form
    [x op y], in which one of [x] and [y] is a variable, the other is its
    known value, and the operation is statically known to produce [k]. *)
let kv_bop (k : Fir.Constant.t) (kv_env : env)
    ~(gen_load : env -> (t * Fir.Env.Record.t) Q.Generator.t) :
    t Q.Generator.t =
  Q.Generator.(
    Let_syntax.(
      let%bind size = size in
      let gen_load = with_size ~size:(size - 1) (gen_load kv_env) in
      Expr_util.gen_kv_refl ~gen_load ~gen_op:(fun l r -> bop k (Two (l, r)))))

let gen (k : Fir.Constant.t) (env : env) ~(gen_arb : env -> t Q.Generator.t)
    ~(gen_load : env -> (t * Fir.Env.Record.t) Q.Generator.t) :
    t Q.Generator.t =
  let kv_env = Fir.Env.filter_to_known_values env in
  Q.Generator.(
    Let_syntax.(
      let%bind size = size in
      weighted_union
        (Utils.My_list.eval_guards
           [ (0 < size, fun () -> (2.0, arb_bop k kv_env ~gen_arb))
           ; ( 0 < size
               && Fir.Env.has_vars_of_prim_type kv_env
                    ~prim:(Fir.Constant.prim_type_of k)
             , fun () -> (3.0, kv_bop k kv_env ~gen_load) )
           ; ( true
             , fun () -> (1.0, Q.Generator.return (Fir.Expression.constant k))
             ) ])))
