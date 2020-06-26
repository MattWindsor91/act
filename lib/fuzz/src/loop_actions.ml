(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

module Surround :
  Action_types.S with type Payload.t = Payload.Cond_surround.t = struct
  let name = Act_common.Id.of_string_list ["flow"; "loop"; "surround"]

  let readme () : string =
    Act_utils.My_string.format_for_readme
      {| Removes a sublist
       of statements from the program, replacing them with a `do... while`
       statement containing some transformation of the removed statements.

       The condition of the `do... while` loop is statically guaranteed to be
       false. |}

  let available (ctx : Availability.Context.t) : bool Or_error.t =
    Ok (ctx |> Availability.Context.subject |> Subject.Test.has_statements)

  module Surround = Payload.Cond_surround

  module Payload = Surround.Make (struct
    let name = name

    let cond_gen :
        Act_fir.Env.t -> Act_fir.Expression.t Base_quickcheck.Generator.t =
      Act_fir.Expression_gen.gen_falsehoods

    let path_filter : Path_filter.t State.Monad.t =
      State.Monad.return Path_filter.empty
  end)

  let wrap_in_loop (cond : Act_fir.Expression.t)
      (statements : Metadata.t Act_fir.Statement.t list) :
      Metadata.t Act_fir.Statement.t =
    Act_fir.Statement.flow
      (Act_fir.Flow_block.while_loop ~kind:Do_while ~cond
         ~body:(Subject.Block.make_generated ~statements ()))

  let run (test : Subject.Test.t) ~(payload : Payload.t) :
      Subject.Test.t State.Monad.t =
    Surround.apply payload ~test ~f:wrap_in_loop
end
