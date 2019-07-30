(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Core
open Act_common

let run (_o : Output.t) (_cfg : Act_config.Act.t) ~(oracle_raw : string)
    ~(subject_raw : string) ~(location_map_raw : string) : unit Or_error.t =
  Or_error.Let_syntax.(
    let%bind oracle_in = Plumbing.Input.of_string_opt (Some oracle_raw) in
    let%bind oracle =
      Act_backend.Output.Observation.load_from_isrc oracle_in
    in
    let%bind subject_in = Plumbing.Input.of_string_opt (Some subject_raw) in
    let%bind subject =
      Act_backend.Output.Observation.load_from_isrc subject_in
    in
    let%bind location_map_in =
      Plumbing.Input.of_string_opt (Some location_map_raw)
    in
    let%bind location_map =
      Act_backend.Diff.Location_map.load_from_isrc location_map_in
    in
    let%map diff = Act_backend.Diff.run ~oracle ~subject ~location_map in
    Act_backend.Diff.pp Fmt.stdout diff)

let readme () =
  Act_utils.My_string.format_for_readme
    {|
    `act diff-states` takes two summaries of backend runs: an
    'oracle' (usually a program _before_ compilation), and a
    'subject' (usually the same program _after_ compilation).  It
    then parses the summaries, applies any provided variable name
    mappings, and compares the sets of final states on both ends.

    Both runs must be in ACT's state JSON format.
  |}

let command : Command.t =
  Command.basic ~summary:"compares two simulation runs" ~readme
    Command.Let_syntax.(
      let%map_open standard_args = ignore anon ; Args.Standard.get
      and oracle_raw = anon ("ORACLE_NAME" %: Filename.arg_type)
      and subject_raw = anon ("SUBJECT_NAME" %: Filename.arg_type)
      and location_map_raw = anon ("LOC_MAP_NAME" %: Filename.arg_type) in
      fun () ->
        Common.lift_command standard_args ~with_compiler_tests:false
          ~f:(run ~oracle_raw ~subject_raw ~location_map_raw))
