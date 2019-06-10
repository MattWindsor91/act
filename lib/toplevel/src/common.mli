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

(** Glue code common to all top-level commands. *)

open Core_kernel
open Act_common

val warn_if_not_tracking_symbols : Output.t -> C_id.t list option -> unit
(** [warn_if_not_tracking_symbols o c_symbols] prints a warning on [o] if
    [c_symbols] is empty. The warning explains that, without any C symbols
    to track, act may make incorrect assumptions. *)

val asm_runner_of_target :
  Act_machine.Target.t -> (module Act_asm.Runner_intf.Basic) Or_error.t
(** [asm_runner_of_target target] gets the runner dependency module
    associated with a target (either a compiler spec or emits clause). *)

val lift_command :
     ?compiler_predicate:Act_compiler.Property.t Blang.t
  -> ?machine_predicate:Act_machine.Property.t Blang.t
  -> ?sanitiser_passes:Act_sanitiser.Pass_group.Selector.t Blang.t
  -> ?with_compiler_tests:bool (* default true *)
  -> f:(Args.Standard.t -> Output.t -> Act_config.Act.t -> unit Or_error.t)
  -> Args.Standard.t
  -> unit
(** [lift_command ?compiler_predicate ?machine_predicate ?sanitiser_passes
    ?with_compiler_tests ~f standard_args] lifts a command body [f],
    performing common book-keeping such as loading and testing the
    configuration, creating an [Output.t], and printing top-level errors. *)

val lift_command_with_files :
     ?compiler_predicate:Act_compiler.Property.t Blang.t
  -> ?machine_predicate:Act_machine.Property.t Blang.t
  -> ?sanitiser_passes:Act_sanitiser.Pass_group.Selector.t Blang.t
  -> ?with_compiler_tests:bool (* default true *)
  -> f:(   Args.Standard_with_files.t
        -> Output.t
        -> Act_config.Act.t
        -> unit Or_error.t)
  -> Args.Standard_with_files.t
  -> unit
(** [lift_command_with_files ?compiler_predicate ?machine_predicate
    ?sanitiser_passes ?with_compiler_tests ~f args] behaves like
    {{!lift_command} lift_command}, but also handles (and supplies) optional
    input and output files. *)

val lift_asm_command_basic :
     f:(   Args.Standard_asm.t
        -> Output.t
        -> Act_config.Act.t
        -> unit Or_error.t)
  -> Args.Standard_asm.t
  -> unit
(** [lift_asm_command_basic ~f args] behaves like
    {{!lift_command_with_files} lift_command_with_files}, but also handles
    (and supplies) the various standard asm command arguments, including
    sanitiser passes. More thorough lifting is left to the [Asm_common]
    module. *)

(** {2 Single-file pipelines}

    These are the common pipelines that most of the single-file commands are
    built upon. *)

val delitmus_compile_asm_pipeline :
     Act_machine.Target.t
  -> (   (module Act_asm.Runner_intf.Basic)
      -> (module Act_asm.Runner_intf.S with type cfg = 'c))
  -> (module Act_asm.Pipeline.S with type cfg = 'c) Or_error.t

val litmusify_pipeline :
     Act_machine.Target.t
  -> (module Act_asm.Pipeline.S
        with type cfg = Sexp.t Act_asm.Litmusifier.Config.t)
     Or_error.t
(** [litmusify_pipeline target] builds a delitmusify-compile-litmusify
    pipeline for target [target]. *)

val make_compiler_input :
     Output.t
  -> Act_common.File_type.t
  -> C_variables.Map.t option
  -> (c_variables:C_variables.Map.t option -> 'cfg)
  -> Set.M(Act_sanitiser.Pass_group).t
  -> Act_c.Filters.Output.t Plumbing.Chain_context.t
  -> 'cfg Act_asm.Job.t Act_compiler.Filter.Chain_input.t
(** [make_compiler_input o file_type user_cvars cfg_fun passes dl_output]
    generates the input to the compiler stage of a single-file pipeline.

    It takes the original file type [file_type]; the user-supplied C
    variables [user_cvars]; a function [cfg_fun] to generate a litmusifier
    configuration given the final C global variable set, the sanitiser
    passes [passes]; and the output from the de-litmus stage of the litmus
    pipeline [dl_output], which contains any postcondition and discovered C
    variables. *)
