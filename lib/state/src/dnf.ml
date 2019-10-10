(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

let predicate_of_state (entry : Entry.t) : string Act_litmus.Predicate.t =
  entry |> Entry.to_alist |> Sequence.of_list
  |> Sequence.map ~f:(fun (k, v) -> Act_litmus.Predicate.eq k v)
  |> Act_litmus.Predicate.optimising_and_seq

let predicate_of_states (states : Set.M(Entry).t) :
    string Act_litmus.Predicate.t =
  states |> Set.to_sequence
  |> Sequence.map ~f:predicate_of_state
  |> Act_litmus.Predicate.optimising_or_seq

let convert_states (entries : Set.M(Entry).t) :
    string Act_litmus.Postcondition.t =
  Act_litmus.Postcondition.make ~quantifier:For_all
    ~predicate:(predicate_of_states entries)

let convert : Observation.t -> string Act_litmus.Postcondition.t =
  Fn.compose convert_states Observation.states

let print_postcondition (oc : Stdio.Out_channel.t) :
    string Act_litmus.Postcondition.t -> unit =
  Fmt.pf
    (Caml.Format.formatter_of_out_channel oc)
    "@[%a@]@."
    (Act_litmus.Postcondition.pp ~pp_const:String.pp)

module Filter :
  Plumbing.Filter_types.S with type aux_i = unit and type aux_o = unit =
Plumbing.Filter.Make (struct
  let name = "DNF"

  type aux_i = unit

  type aux_o = unit

  let run (ctx : unit Plumbing.Filter_context.t) (ic : Stdio.In_channel.t)
      (oc : Stdio.Out_channel.t) : unit Or_error.t =
    let path = Plumbing.Filter_context.input_path_string ctx in
    Or_error.(
      ic
      |> Observation.load_from_ic ~path
      >>| convert >>| print_postcondition oc)
end)