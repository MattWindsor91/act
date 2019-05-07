(* This file is part of 'act'.

   Copyright (c) 2018, 2019 by Matt Windsor

   Permission is hereby granted, free of charge, to any person obtaining a
   copy of this software and associated documentation files (the
   "Software"), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to permit
   persons to whom the Software is furnished to do so, subject to the
   following conditions:

   The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
   NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
   OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
   USE OR OTHER DEALINGS IN THE SOFTWARE. *)

open Core_kernel
open Travesty_core_kernel_exts
open Act_common
include Instance_intf
module Machine_assoc = Alist.Fix_left (Config.Machine.Id)

(** Compiler specification sets, grouped by machine. *)
module Compiler_spec_env = struct
  include Machine_assoc.Fix_right (Config.Compiler.Spec.Set)

  let group_by_machine specs =
    specs
    |> Config.Compiler.Spec.Set.group ~f:(fun spec ->
           Config.Machine.Spec.With_id.id
             (Config.Compiler.Spec.With_id.machine spec) )
    |> Id.Map.to_alist

  let get (cfg : Run_config.t) (compilers : Config.Compiler.Spec.Set.t) : t
      =
    let enabled_ids = Run_config.compilers cfg in
    let specs = Config.Compiler.Spec.Set.restrict compilers enabled_ids in
    group_by_machine specs
end

(** Bundle of everything used in a tester job. *)
module Job = struct
  type t =
    { config: Run_config.t
    ; specs: Compiler_spec_env.t
    ; c_simulations: Sim.Bulk.File_map.t
    ; make_machine: Config.Compiler.Spec.Set.t -> (module Machine.S) }
  [@@deriving fields, make]

  let run_machine (job : t) (mach_id, mach_compilers) =
    Or_error.Let_syntax.(
      let (module TM) = (make_machine job) mach_compilers in
      let%map analysis = TM.run (config job) (c_simulations job) in
      (mach_id, analysis))

  let run (job : t) : Analysis.Machine.t Machine_assoc.t Or_error.t =
    job |> specs |> List.map ~f:(run_machine job) |> Or_error.combine_errors
end

module Make (B : Basic) : S = struct
  include B
  include Common.Extend (B)

  let make_analysis (raw : Analysis.Machine.t Machine_assoc.t T.t) :
      Analysis.t =
    Analysis.make ~machines:(T.value raw) ?time_taken:(T.time_taken raw) ()

  let make_machine (mach_compilers : Config.Compiler.Spec.Set.t) =
    ( module Machine.Make (struct
      include B

      (* Reduce the set of compilers to those specifically used in this
         machine. *)
      let compilers = mach_compilers
    end)
    : Machine.S )

  module H = C_sim.Make (B.C_simulator)
  module S = Sim.Bulk.Make (B.C_simulator)

  let make_output_path (ps : Pathset.Run.t) : (Fpath.t -> Fpath.t) Staged.t
      =
    Staged.stage (fun input_path ->
        let name = Fpath.(basename (rem_ext input_path)) in
        Pathset.Run.c_sim_file ps name )

  let run_c_simulations (config : Run_config.t) :
      Sim.Bulk.File_map.t Or_error.t =
    let input_paths = Run_config.c_litmus_files config in
    let ps = Run_config.pathset config in
    let output_path_f = Staged.unstage (make_output_path ps) in
    let job = {S.Job.arch= C; input_paths; output_path_f} in
    S.run job

  let make_job (config : Run_config.t) : Job.t Or_error.t =
    Or_error.Let_syntax.(
      let%map c_simulations = run_c_simulations config in
      let specs = Compiler_spec_env.get config compilers in
      Job.make ~config ~c_simulations ~specs ~make_machine)

  let run_job_timed (job : Job.t) :
      Analysis.Machine.t Machine_assoc.t T.t Or_error.t =
    T.bracket_join (fun () -> Job.run job)

  let run (config : Run_config.t) : Analysis.t Or_error.t =
    Or_error.(config |> make_job >>= run_job_timed >>| make_analysis)
end
