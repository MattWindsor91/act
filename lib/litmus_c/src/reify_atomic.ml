(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

open struct
  module Fir = Act_fir
  module Prim = Reify_prim
end

let known_call (name : string) (args : Ast.Expr.t list) : Ast.Expr.t =
  Call {func= Identifier (Act_common.C_id.of_string name); arguments= args}

let mem_order (mo : Fir.Mem_order.t) : Ast.Expr.t =
  Identifier (Act_common.C_id.of_string (Fir.Mem_order.to_string mo))

let cmpxchg (cmpxchg : 'e Fir.Atomic_cmpxchg.t) ~(expr : 'e -> Ast.Expr.t) :
    Ast.Expr.t =
  Fir.(
    Atomic_cmpxchg.(
      known_call Abstract_atomic.cmpxchg_name
        [ Prim.address (obj cmpxchg)
        ; Prim.address (expected cmpxchg)
        ; expr (desired cmpxchg)
        ; mem_order (succ cmpxchg)
        ; mem_order (fail cmpxchg) ]))

let fence (fence : Fir.Atomic_fence.t) : Ast.Expr.t =
  let call = Abstract_atomic.fence_name (Fir.Atomic_fence.mode fence) in
  known_call call [mem_order (Fir.Atomic_fence.mo fence)]

let fetch (f : 'e Fir.Atomic_fetch.t) ~(expr : 'e -> Ast.Expr.t) : Ast.Expr.t
    =
  Fir.(
    Atomic_fetch.(
      known_call
        (Abstract_atomic.fetch_name (op f))
        [Prim.address (obj f); expr (arg f); mem_order (mo f)]))

let load (ld : Fir.Atomic_load.t) : Ast.Expr.t =
  Fir.(
    Atomic_load.(
      known_call Abstract_atomic.load_name
        [Prim.address (src ld); mem_order (mo ld)]))

let store (st : Fir.Atomic_store.t) ~(expr : 'e -> Ast.Expr.t) : Ast.Expr.t =
  Fir.(
    Atomic_store.(
      known_call Abstract_atomic.store_name
        [Prim.address (dst st); expr (src st); mem_order (mo st)]))

let xchg (xc : 'e Fir.Atomic_xchg.t) ~(expr : 'e -> Ast.Expr.t) : Ast.Expr.t
    =
  Fir.(
    Atomic_xchg.(
      known_call Abstract_atomic.xchg_name
        [Prim.address (obj xc); expr (desired xc); mem_order (mo xc)]))

let reify_expr (x : 'e Fir.Atomic_expression.t) ~(expr : 'e -> Ast.Expr.t) :
    Ast.Expr.t =
  Fir.Atomic_expression.reduce x ~cmpxchg:(cmpxchg ~expr)
    ~fetch:(fetch ~expr) ~load ~xchg:(xchg ~expr)

let expr_stm (x : Ast.Expr.t) : Ast.Stm.t = Expr (Some x)

let reify_stm (x : Fir.Atomic_statement.t)
    ~(expr : Fir.Expression.t -> Ast.Expr.t) : Ast.Stm.t =
  x
  |> Fir.Atomic_statement.reduce ~cmpxchg:(cmpxchg ~expr)
       ~fetch:(fetch ~expr) ~fence ~store:(store ~expr) ~xchg:(xchg ~expr)
  |> expr_stm