(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
module Src = Act_c_mini
module Q = Base_quickcheck
module Qx = Act_utils.My_quickcheck

let printer (e : Src.Expression.t) : unit =
  e |> Src.Reify_expr.reify |> Fmt.(pr "@[%a@]@." Act_c_lang.Ast.Expr.pp)

let print_sample (module G : Src.Expression_gen.S) : unit =
  (* Expressions are quite big, so we tone down the generation parameters a
     bit. *)
  Qx.print_sample ~test_count:5 ~printer
    ( module struct
      include Src.Expression
      include G
    end )

let test_all_expressions_have_type
    (f :
         (module Src.Env_types.S_with_known_values)
      -> (module Q.Test.S with type t = Src.Expression.t)) (ty : Src.Type.t)
    : unit =
  let env = Lazy.force Env.test_env_mod in
  let (module Qc) = f env in
  let module Ty = Src.Expression.Type_check ((val env)) in
  Q.Test.run_exn
    (module Qc)
    ~f:(fun e ->
      [%test_result: Src.Type.t Or_error.t] (Ty.type_of e) ~here:[[%here]]
        ~equal:[%compare.equal: Src.Type.t Or_error.t]
        ~expect:(Or_error.return ty))

module Exp_idents =
  Travesty.Traversable.Chain0
    (Act_c_mini.Expression_traverse.On_lvalues)
    (Act_c_mini.Lvalue.On_identifiers)

let test_all_expressions_in_env
    (f :
         (module Src.Env_types.S_with_known_values)
      -> (module Q.Test.S with type t = Src.Expression.t)) : unit =
  let (module E) = Lazy.force Env.test_env_mod in
  let (module Q) = f (module E) in
  Base_quickcheck.Test.run_exn
    (module Q)
    ~f:
      ([%test_pred: Src.Expression.t]
         (Exp_idents.for_all ~f:(Map.mem E.env))
         ~here:[[%here]])

let test_all_expressions_evaluate
    (f :
         (module Src.Env_types.S_with_known_values)
      -> (module Q.Test.S with type t = Src.Expression.t))
    ~(pred : Src.Constant.t -> bool) : unit =
  let env_mod = Lazy.force Env.test_env_mod in
  let env = Src.Heap.make (Src.Address.eval_on_env env_mod) in
  let (module Qc) = f env_mod in
  Q.Test.run_exn
    (module Qc)
    ~f:(fun e ->
      [%test_result: bool Or_error.t]
        (let k_result = Src.Expression_eval.as_constant ~env e in
         Or_error.map ~f:pred k_result)
        ~expect:(Or_error.return true)
        ~equal:[%compare.equal: bool Or_error.t] ~here:[[%here]])

let%test_module "Int_values" =
  ( module struct
    let print_sample (module E : Src.Env_types.S_with_known_values) =
      print_sample (module Src.Expression_gen.Int_values (E))

    let%expect_test "sample" =
      print_sample (Lazy.force Env.test_env_mod) ;
      [%expect
        {|
      -1
      foo
      atomic_fetch_sub_explicit(&y, foo - foo, memory_order_relaxed)
      atomic_load_explicit(bar, memory_order_consume) |}]

    let%expect_test "sample (environment has only atomic_int*)" =
      print_sample (Lazy.force Env.test_env_atomic_ptrs_only_mod) ;
      [%expect
        {|
      -209
      -1
      0
      atomic_fetch_sub_explicit(bar,
                                atomic_load_explicit(bar, memory_order_seq_cst) -
                                atomic_load_explicit(bar, memory_order_seq_cst),
                                memory_order_relaxed)
      atomic_fetch_add_explicit(bar, 0, memory_order_seq_cst) -
      atomic_fetch_add_explicit(bar, 0, memory_order_seq_cst) |}]

    let%expect_test "sample (environment is empty)" =
      print_sample (Lazy.force Env.empty_env_mod) ;
      [%expect
        {|
      -23556581
      -209
      -1
      -32276 - -32276
      0 - 0 |}]

    let%test_unit "all expressions have 'int' type" =
      test_all_expressions_have_type
        (fun e -> (module Src.Expression_gen.Int_values ((val e))))
        Src.Type.(int ())

    let%test_unit "all referenced variables in environment" =
      test_all_expressions_in_env (fun e ->
          (module Src.Expression_gen.Int_values ((val e))))
  end )


let%test_module "Int zeroes" =
  ( module struct
    let print_sample (module E : Src.Env_types.S_with_known_values) =
      print_sample (module Src.Expression_gen.Int_zeroes (E))

    let%expect_test "sample" =
      print_sample (Lazy.force Env.test_env_mod) ;
      [%expect
        {|
          0
          -190264 - -190264
          atomic_fetch_sub_explicit(&y, 0, memory_order_seq_cst) -
          atomic_fetch_sub_explicit(&y, 0, memory_order_seq_cst) |}]

    let test_fun (module E : Src.Env_types.S_with_known_values) :
        (module Q.Test.S with type t = Src.Expression.t) =
      (module Src.Expression_gen.Int_zeroes (E))

    let%test_unit "all expressions have 'int' type" =
      test_all_expressions_have_type test_fun Src.Type.(int ())

    let%test_unit "all expressions evaluate to 0" =
      test_all_expressions_evaluate test_fun ~pred:(fun x ->
          match Src.Constant.as_int x with Ok 0 -> true | _ -> false)

    let%test_unit "all referenced variables in environment" =
      test_all_expressions_in_env (fun e ->
          (module Src.Expression_gen.Int_zeroes ((val e))))
  end )

let%test_module "Bool_values" =
  ( module struct
    let print_sample (module E : Src.Env_types.S_with_known_values) =
      print_sample (module Src.Expression_gen.Bool_values (E))

    let%expect_test "sample" =
      print_sample (Lazy.force Env.test_env_mod) ;
      [%expect
        {|
      -326 == *blep
      *blep == foo
      atomic_fetch_add_explicit(bar, atomic_load_explicit(&x, memory_order_seq_cst)
                                - atomic_load_explicit(&x, memory_order_seq_cst),
                                memory_order_seq_cst)
      == foo
      barbaz && !barbaz
      barbaz || barbaz |}]

    let%expect_test "sample (environment has only atomic_int*)" =
      print_sample (Lazy.force Env.test_env_atomic_ptrs_only_mod) ;
      [%expect
        {|
      atomic_load_explicit(bar, memory_order_acquire) ==
      atomic_load_explicit(bar, memory_order_acquire)
      (!(true && atomic_load_explicit(bar, memory_order_acquire) ==
         atomic_load_explicit(bar, memory_order_seq_cst))
       ||
       !(85 ==
         atomic_fetch_add_explicit(bar,
                                   atomic_load_explicit(bar, memory_order_acquire)
                                   -
                                   atomic_load_explicit(bar, memory_order_acquire),
                                   memory_order_seq_cst)))
      &&
      (!(45766 == -1 && true) &&
       (false && 61684972 == 2869 &&
        (210 == atomic_load_explicit(bar, memory_order_consume) ||
         atomic_load_explicit(bar, memory_order_acquire) ==
         atomic_load_explicit(bar, memory_order_consume))))
      atomic_load_explicit(bar, memory_order_seq_cst) ==
      atomic_load_explicit(bar, memory_order_seq_cst) || true
      atomic_load_explicit(bar, memory_order_seq_cst) ==
      atomic_load_explicit(bar, memory_order_acquire) || -15464318 ==
      atomic_load_explicit(bar, memory_order_consume) ||
      atomic_fetch_sub_explicit(bar,
                                atomic_load_explicit(bar, memory_order_seq_cst) -
                                atomic_load_explicit(bar, memory_order_seq_cst),
                                memory_order_acq_rel)
      == -859284515 - -859284515
      !false || -1 == atomic_fetch_sub_explicit(bar, 0, memory_order_relaxed) ||
      (-50348097 == atomic_load_explicit(bar, memory_order_relaxed) ||
       atomic_load_explicit(bar, memory_order_acquire) ==
       atomic_load_explicit(bar, memory_order_consume))
      && (33209 == 14202 && 489744 == -34) |}]

    let%expect_test "sample (environment is empty)" =
      print_sample (Lazy.force Env.empty_env_mod) ;
      [%expect
        {|
      -1 == 0 - 0
      18 == 320421
      -22537 - -22537 == -28705
      -859284515 == 0 && !false
      (-15464318 == -2147483648 || -3937 == -52910) && true |}]

    let test_fun (module E : Src.Env_types.S_with_known_values) =
      (module Src.Expression_gen.Bool_values (E) : Q.Test.S
        with type t = Src.Expression.t )

    let%test_unit "all expressions have 'bool' type" =
      test_all_expressions_have_type test_fun Src.Type.(bool ())

    (* TODO(@MattWindsor91): we can't currently check that all expressions
       evaluate safely to Booleans, as the evaluator and known values tracker
       don't understand atomic loads. *)

    let%test_unit "all referenced variables in environment" =
      test_all_expressions_in_env (fun e ->
          (module Src.Expression_gen.Bool_values ((val e))))
  end )

let%test_module "Bool falsehoods" =
  ( module struct
    let print_sample (module E : Src.Env_types.S_with_known_values) =
      let module B = Src.Expression_gen.Bool_known (E) in
      print_sample (module B.Falsehoods)

    let%expect_test "sample" =
      print_sample (Lazy.force Env.test_env_mod) ;
      [%expect
        {|
          false
          false && barbaz
          (barbaz || atomic_load_explicit(&x, memory_order_seq_cst) == -209) &&
          (*blep == atomic_load_explicit(&y, memory_order_seq_cst) &&
           atomic_load_explicit(&y, memory_order_relaxed) ==
           atomic_load_explicit(bar, memory_order_consume))
          && false
          false || (barbaz || barbaz) && barbaz && false |}]

    let test_fun (module E : Src.Env_types.S_with_known_values) :
        (module Q.Test.S with type t = Src.Expression.t) =
      let module K = Src.Expression_gen.Bool_known (E) in
      (module K.Falsehoods)

    let%test_unit "all expressions have 'bool' type" =
      test_all_expressions_have_type test_fun Src.Type.(bool ())

    let%test_unit "all expressions evaluate to 'false'" =
      test_all_expressions_evaluate test_fun ~pred:(fun x ->
          match Src.Constant.as_bool x with Ok b -> not b | _ -> false)

    let%test_unit "all referenced variables in environment" =
      test_all_expressions_in_env (fun e ->
          (module Src.Expression_gen.Bool_values ((val e))))
  end )

let%test_module "Bool tautologies" =
  ( module struct
    let print_sample (module E : Src.Env_types.S_with_known_values) =
      let module B = Src.Expression_gen.Bool_known (E) in
      print_sample (module B.Tautologies)

    let%expect_test "sample" =
      print_sample (Lazy.force Env.test_env_mod) ;
      [%expect
        {|
          true
          atomic_load_explicit(&z, memory_order_seq_cst) == false
          true || barbaz
          11 == foo ||
          (foo == *blep || *blep == atomic_load_explicit(&y, memory_order_relaxed)) ||
          !(false && true) |}]

    let test_fun (module E : Src.Env_types.S_with_known_values) :
        (module Q.Test.S with type t = Src.Expression.t) =
      let module K = Src.Expression_gen.Bool_known (E) in
      (module K.Tautologies)

    let%test_unit "all expressions have 'bool' type" =
      test_all_expressions_have_type test_fun Src.Type.(bool ())

    let%test_unit "all expressions evaluate to 'true'" =
      test_all_expressions_evaluate test_fun ~pred:(fun x ->
          match Src.Constant.as_bool x with Ok b -> b | _ -> false)

    let%test_unit "all referenced variables in environment" =
      test_all_expressions_in_env (fun e ->
          (module Src.Expression_gen.Bool_values ((val e))))
  end )
