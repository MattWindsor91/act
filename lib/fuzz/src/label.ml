(* This file is part of c4f.

   Copyright (c) 2018-2021 C4 Project

   c4t itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   Parts of c4t are based on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

open struct
  module A = Accessor_base
  module Ac = Act_common
end

module Stm = Act_fir.Statement_traverse.With_meta (Unit)

let labels_of_thread (tid : int)
    (thread : unit Act_fir.Function.t Ac.C_named.t) :
    Act_common.Litmus_id.t list =
  thread |> A.get Ac.C_named.value |> Act_fir.Function.body_stms
  |> List.concat_map ~f:Stm.On_primitives.to_list
  (* TODO(@MattWindsor91): push this further *)
  |> List.filter_map ~f:(fun x ->
         Option.(
           A.(x.@?(Act_fir.Prim_statement.label))
           >>| Act_common.Litmus_id.local tid))

let labels_of_test (test : Act_fir.Litmus.Test.t) :
    Set.M(Act_common.Litmus_id).t =
  test |> Act_fir.Litmus.Test.threads
  |> List.concat_mapi ~f:labels_of_thread
  |> Set.of_list (module Act_common.Litmus_id)

let gen_fresh (set : Set.M(Ac.Litmus_id).t) :
    Ac.C_id.t Base_quickcheck.Generator.t =
  let flat_set =
    Set.map (module Ac.C_id) ~f:Ac.Litmus_id.variable_name set
  in
  Base_quickcheck.Generator.(
    Ac.C_id.Human.quickcheck_generator
    |> filter ~f:(Fn.non (Set.mem flat_set)))
