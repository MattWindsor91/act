(* The Automagic Compiler Tormentor

   Copyright (c) 2018, 2019, 2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
open Import

let print_flags : Set.M(Src.Path_flag).t -> unit =
  Fmt.pr "@[%a@]@." Src.Path_flag.pp_set

let%test_module "flags_of_metadata" =
  ( module struct
    let test (m : Src.Metadata.t) : unit =
      print_flags (Src.Path_flag.flags_of_metadata m)

    let%expect_test "existing" =
      test Src.Metadata.Existing ;
      [%expect {| {execute-multi-unsafe} |}]

    let%expect_test "dead-code" =
      test Src.Metadata.gen_dead ;
      [%expect {| {in-dead-code} |}]

    let%expect_test "normal generation" =
      test Src.Metadata.gen_normal ;
      [%expect {| {} |}]

    let%expect_test "normal-with-restrictions generation" =
      test
        Src.Metadata.(
          Generated
            (Gen.make
               ~restrictions:(Set.singleton (module Restriction) Once_only)
               ())) ;
      [%expect {| {execute-multi-unsafe} |}]

    let%expect_test "once generation" =
      test Src.Metadata.gen_once ;
      [%expect {| {} |}]
  end )

let%test_module "flags_of_flow" =
  ( module struct
    let test (f : Src.Subject.Statement.Flow.t) : unit =
      print_flags (Src.Path_flag.flags_of_flow f)

    let%expect_test "generated loop" =
      test
        (Fir.Flow_block.while_loop
           ~cond:(Fir.Expression.of_variable_str_exn "foo")
           ~kind:While
           ~body:(Src.Subject.Block.make_generated ())) ;
      [%expect {| {in-execute-multi, in-loop} |}]

    let%expect_test "existing loop" =
      test
        (Fir.Flow_block.while_loop
           ~cond:(Fir.Expression.of_variable_str_exn "foo")
           ~kind:While
           ~body:(Src.Subject.Block.make_existing ())) ;
      [%expect {| {in-execute-multi, in-loop} |}]

    let%expect_test "dead loop" =
      test
        (Fir.Flow_block.while_loop
           ~cond:(Fir.Expression.of_variable_str_exn "foo")
           ~kind:While
           ~body:(Src.Subject.Block.make_dead_code ())) ;
      [%expect {| {in-loop} |}]

    let%expect_test "dead implicit" =
      test (Fir.Flow_block.implicit (Src.Subject.Block.make_dead_code ())) ;
      [%expect {| {} |}]
  end )
