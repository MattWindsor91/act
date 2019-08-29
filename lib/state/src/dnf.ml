(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

let predicate_of_state (entry: Entry.t) :
  string Act_litmus.Postcondition.Pred.t =
  entry
  |> Entry.to_alist
  |> Act_litmus.Postcondition.Pred.(
      List.fold ~init:(bool true)
        ~f:(fun acc (k, v) -> Infix.( acc &&+ (k ==? v))))


let predicate_of_states : Set.M(Entry).t ->
  string Act_litmus.Postcondition.Pred.t =
  Act_litmus.Postcondition.Pred.(
  Set.fold ~init:(bool true)
    ~f:(fun acc entry -> Infix.( acc ||+ (predicate_of_state entry))))

let convert_states (entries: Set.M(Entry).t) :
  string Act_litmus.Postcondition.t =
  Act_litmus.Postcondition.make ~quantifier:For_all
    ~predicate:(predicate_of_states entries)

let convert :
     Observation.t
     -> string Act_litmus.Postcondition.t =
     Fn.compose convert_states Observation.witnesses


module Filter :
  Plumbing.Filter_types.S with type aux_i = unit
                           and type aux_o = unit =
Plumbing.Filter.Make (struct
  let name = "DNF"

  type aux_i = unit
  type aux_o = unit

  let run (ctx : unit Plumbing.Filter_context.t) (ic : Stdio.In_channel.t) (oc : Stdio.Out_channel.t) : unit Or_error.t =
    Or_error.Let_syntax.(
      let%map obs = Observation.load_from_ic ~path:(Plumbing.(Input.to_string (Filter_context.input ctx))) ic in
      let dnf = convert obs in
      Fmt.pf (Caml.Format.formatter_of_out_channel oc) "@[%a@]@."
        (Act_litmus.Postcondition.pp ~pp_const:String.pp)
        dnf
    )
end)
