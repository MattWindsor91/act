(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
open Import

module Test_data = struct
  let cmpxchg : Act_fir.Expression.t Act_fir.Atomic_cmpxchg.t Lazy.t =
    lazy
      Act_fir.(
        Atomic_cmpxchg.make
          ~obj:(Address.of_variable_str_exn "gen1")
          ~expected:
            (Accessor.construct Address.variable_ref
               (Act_common.C_id.of_string "expected"))
          ~desired:(Expression.int_lit 54321)
          ~succ:Seq_cst ~fail:Relaxed)

  let cmpxchg_payload : Src.Atomic_cmpxchg.Insert.Inner_payload.t Lazy.t =
    Lazy.map cmpxchg ~f:(fun cmpxchg ->
        Src.Atomic_cmpxchg.Insert.Inner_payload.
          { cmpxchg
          ; exp_val= Act_fir.Constant.int 12345
          ; exp_var= Act_common.Litmus_id.of_string "0:expected"
          ; out_var= Act_common.Litmus_id.of_string "0:out" })
end

let%test_module "cmpxchg.make.int.succeed" =
  ( module struct
    let random_state : Src.Atomic_cmpxchg.Insert.Int_succeed.Payload.t Lazy.t
        =
      Lazy.Let_syntax.(
        let%bind to_insert = Test_data.cmpxchg_payload in
        let%map where = Fuzz_test.Subject.Test_data.Path.insert_live in
        Fuzz.Payload_impl.Pathed.make to_insert ~where)

    let test_action : Fuzz.Subject.Test.t Fuzz.State.Monad.t =
      Fuzz.State.Monad.(
        Storelike.Test_common.prepare_fuzzer_state ()
        >>= fun () ->
        Src.Atomic_cmpxchg.Insert.Int_succeed.run
          (Lazy.force Fuzz_test.Subject.Test_data.test)
          ~payload:(Lazy.force random_state))

    let%expect_test "programs" =
      Fuzz_test.Action.Test_utils.run_and_dump_test test_action
        ~initial_state:(Lazy.force Fuzz_test.Subject.Test_data.state) ;
      [%expect
        {|
      void
      P0(atomic_int *gen1, atomic_int *gen2, int *gen3, int *gen4, atomic_int *x,
         atomic_int *y)
      {
          int expected = 12345;
          bool out = true;
          atomic_int r0 = 4004;
          int r1 = 8008;
          atomic_store_explicit(x, 42, memory_order_seq_cst);
          ;
          out =
          atomic_compare_exchange_strong_explicit(gen1, &expected, 54321,
                                                  memory_order_seq_cst,
                                                  memory_order_relaxed);
          atomic_store_explicit(y, foo, memory_order_relaxed);
          if (foo == y)
          { atomic_store_explicit(x, 56, memory_order_seq_cst); kappa_kappa: ; }
          if (false)
          {
              atomic_store_explicit(y,
                                    atomic_load_explicit(x, memory_order_seq_cst),
                                    memory_order_seq_cst);
          }
          do { atomic_store_explicit(x, 44, memory_order_seq_cst); } while (4 ==
          5);
          for (r1 = 0; r1 <= 2; r1++)
          { atomic_store_explicit(x, 99, memory_order_seq_cst); }
          while (4 == 5) { atomic_store_explicit(x, 44, memory_order_seq_cst); }
      }

      void
      P1(atomic_int *gen1, atomic_int *gen2, int *gen3, int *gen4, atomic_int *x,
         atomic_int *y)
      { loop: ; if (true) {  } else { goto loop; } } |}]

    let%expect_test "global variables" =
      Storelike.Test_common.run_and_dump_globals test_action
        ~initial_state:(Lazy.force Fuzz_test.Subject.Test_data.state) ;
      [%expect {| gen1= gen2=-55 gen3=1998 gen4=-4 x= y= |}]

    let%expect_test "variables with known values" =
      Storelike.Test_common.run_and_dump_kvs test_action
        ~initial_state:(Lazy.force Fuzz_test.Subject.Test_data.state) ;
      [%expect
        {| expected=12345 gen2=-55 gen3=1998 gen4=-4 out=true r0=4004 r1=8008 |}]

    let%expect_test "variables with dependencies" =
      Storelike.Test_common.run_and_dump_deps test_action
        ~initial_state:(Lazy.force Fuzz_test.Subject.Test_data.state) ;
      [%expect {| expected=12345 gen1= |}]

    (* TODO(@MattWindsor91): dedupe this with the above *)
    let payload_dead : Src.Atomic_cmpxchg.Insert.Int_succeed.Payload.t Lazy.t
        =
      Lazy.Let_syntax.(
        let%bind to_insert = Test_data.cmpxchg_payload in
        let%map where = Fuzz_test.Subject.Test_data.Path.insert_dead in
        Fuzz.Payload_impl.Pathed.make to_insert ~where)

    let test_action_dead : Fuzz.Subject.Test.t Fuzz.State.Monad.t =
      Fuzz.State.Monad.(
        Storelike.Test_common.prepare_fuzzer_state ()
        >>= fun () ->
        Src.Atomic_cmpxchg.Insert.Int_succeed.run
          (Lazy.force Fuzz_test.Subject.Test_data.test)
          ~payload:(Lazy.force payload_dead))

    let%expect_test "variables with dependencies, in dead-code" =
      Storelike.Test_common.run_and_dump_deps test_action_dead
        ~initial_state:(Lazy.force Fuzz_test.Subject.Test_data.state) ;
      [%expect {| |}]
  end )
