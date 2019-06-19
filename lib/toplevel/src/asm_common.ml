(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

include Base
module Tx = Travesty_base_exts
module Ac = Act_common
module Pb = Plumbing

module Input = struct
  type t =
    { act_config: Act_config.Act.t
    ; args: Args.Standard_asm.t
    ; sanitiser_passes: Set.M(Act_sanitiser.Pass_group).t
    ; c_litmus_aux: Act_delitmus.Aux.t
    ; target: Act_machine.Target.t
    ; pb_input: Plumbing.Input.t
    ; pb_output: Plumbing.Output.t
    ; output: Act_common.Output.t }
  [@@deriving fields]

  let make_job_input (i : t) (config_fn : Act_delitmus.Aux.t -> 'cfg)
      : 'cfg Act_asm.Job.t =
    let aux = c_litmus_aux i in
    let config = config_fn aux in
    Act_asm.Job.make ~config ~passes:(sanitiser_passes i) ()
end

let resolve_target (args : Args.Standard_asm.t) (cfg : Act_config.Act.t) :
    Act_machine.Target.t Or_error.t =
  let raw_target = Args.Standard_asm.target args in
  Asm_target.resolve ~cfg raw_target

let no_aux_warning : string =
  {|
    Warning: no 'aux file' was provided on the command line.

    Without an aux file, ACT can't tell what the correct Litmus postcondition,
    locations, initial values, or mappings between variable names are, and may
    produce erroneous output.

    To supply an aux file, pass '-aux-file path' at the command line.
 |}

let warn_no_aux (o : Act_common.Output.t) : unit =
  Ac.Output.pw o "@[%a@]@." Fmt.paragraphs no_aux_warning

let get_aux (args : Args.Standard_asm.t) ~(output : Act_common.Output.t) :
    Act_delitmus.Aux.t Or_error.t =
  match Args.Standard_asm.aux_file args with
  | Some auxf ->
    Or_error.(
      Some auxf |> Pb.Input.of_string_opt >>=
      Act_delitmus.Aux.load_from_isrc
    )
  | None ->
    warn_no_aux output;
    Or_error.return Act_delitmus.Aux.empty

let with_input (args : Args.Standard_asm.t) (output : Ac.Output.t)
    (act_config : Act_config.Act.t) ~(f : Input.t -> unit Or_error.t)
    ~(default_passes : Set.M(Act_sanitiser.Pass_group).t) : unit Or_error.t
    =
  let sanitiser_passes =
    Act_config.Act.sanitiser_passes act_config ~default:default_passes
  in
  Or_error.Let_syntax.(
    let%bind c_litmus_aux = get_aux args ~output in
    let%bind target = resolve_target args act_config in
    let%bind pb_input = Args.Standard_asm.infile_source args in
    let%bind pb_output = Args.Standard_asm.outfile_sink args in
    let input =
      Input.Fields.create ~act_config ~output ~args ~sanitiser_passes
        ~c_litmus_aux ~target ~pb_input ~pb_output
    in
    f input)

let lift_command (args : Args.Standard_asm.t)
    ~(f : Input.t -> unit Or_error.t)
    ~(default_passes : Set.M(Act_sanitiser.Pass_group).t) : unit =
  Common.lift_asm_command_basic args ~f:(with_input ~f ~default_passes)
