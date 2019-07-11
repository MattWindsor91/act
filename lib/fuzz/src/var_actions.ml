(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

module Global_random_state = struct
  type t = {is_atomic: bool; initial_value: int; name: Act_common.C_id.t}
  [@@deriving sexp]
end

module Make_global :
  Action_types.S with type Random_state.t = Global_random_state.t = struct
  let name = Act_common.Id.of_string "var.make.global"

  let readme () =
    Act_utils.My_string.format_for_readme
      {|
    Generates a new global integer variable, with a random name, initial value,
    and atomicity.
    |}

  let default_weight = 2

  module Random_state = struct
    include Global_random_state
    module G = Base_quickcheck.Generator

    let gen' (vars : Var.Map.t) : t G.t =
      let open G.Let_syntax in
      let%bind is_atomic = G.bool in
      let%bind initial_value =
        Act_c_lang.Ast_basic.Constant.gen_int32_as_int
      in
      let%map name = Var.Map.gen_fresh_var vars in
      {is_atomic; initial_value; name}

    let gen (_subject : Subject.Test.t) : t G.t State.Monad.t =
      State.Monad.with_vars gen'
  end

  let available = Action.always

  let run (subject : Subject.Test.t)
      ({is_atomic; initial_value; name} : Random_state.t) :
      Subject.Test.t State.Monad.t =
    let ty = Act_c_mini.Type.int_type ~is_atomic ~is_pointer:true in
    let open State.Monad.Let_syntax in
    let%map () =
      State.Monad.register_global ty name
        ~initial_value:(Var.Value.Int initial_value)
    in
    let const = Act_c_lang.Ast_basic.Constant.Integer initial_value in
    Subject.Test.add_var_to_init subject name const
end