(* This file is part of 'act'.

Copyright (c) 2018 by Matt Windsor

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. *)

(** Glue code common to all top-level commands *)

open Core_kernel
open Lib
open Utils

val warn_if_not_tracking_symbols
  :  Output.t
  -> string list option
  -> unit
(** [warn_if_not_tracking_symbols o c_symbols] prints a warning on [o]
    if [c_symbols] is empty.  The warning explains that, without any
    C symbols to track, act may make incorrect assumptions. *)

val get_target
  :  Lib.Config.M.t
  -> [< `Id of Id.t | `Arch of Id.t ]
  -> Compiler.Target.t Or_error.t
(** [get_target cfg target] processes a choice between compiler ID
    and architecture ID; if the input is a compiler
    ID, the compiler is retrieved from [cfg]. *)

val asm_runner_of_target : Compiler.Target.t -> (module Asm_job.Runner) Or_error.t
(** [asm_runner_of_target target] gets the [Asm_job.Runner]
   associated with a target (either a compiler spec or emits
   clause). *)

module Chain_with_delitmus
    (Onto  : Filter.S)
  : Filter.S with type aux_i = (File_type.t_or_infer * (C.Filters.Output.t Filter.chain_output -> Onto.aux_i))
              and type aux_o = (C.Filters.Output.t option * Onto.aux_o)
(** Chain a delitmusing pass onto [Onto] conditional on the incoming
   file type. *)

val chain_with_delitmus
  :  (module Filter.S with type aux_i = 'i and type aux_o = 'o)
  -> ( module Filter.S with type aux_i = (File_type.t_or_infer * (C.Filters.Output.t Filter.chain_output -> 'i))
                        and type aux_o = (C.Filters.Output.t option * 'o)
     )
(** [chain_with_delitmus onto] is [Chain_with_delitmus], but lifted to
   first-class modules for conveniently slotting into chain builder
   pipelines. *)

val lift_command
  :  ?compiler_predicate:Compiler.Property.t Blang.t
  -> ?machine_predicate:Machine.Property.t Blang.t
  -> ?sanitiser_passes:Sanitiser_pass.Selector.t Blang.t
  -> ?with_compiler_tests:bool (* default true *)
  -> f:(Args.Standard.t -> Output.t -> Lib.Config.M.t -> unit Or_error.t)
  -> Args.Standard.t
  -> unit
(** [lift_command ?compiler_predicate ?machine_predicate
   ?sanitiser_passes ?with_compiler_tests ~f standard_args] lifts a
   command body [f], performing common book-keeping such as loading
   and testing the configuration, creating an [Output.t], and printing
   top-level errors. *)

val lift_command_with_files
  :  ?compiler_predicate:Compiler.Property.t Blang.t
  -> ?machine_predicate:Machine.Property.t Blang.t
  -> ?sanitiser_passes:Sanitiser_pass.Selector.t Blang.t
  -> ?with_compiler_tests:bool (* default true *)
  -> f:(Args.Standard_with_files.t -> Output.t -> Lib.Config.M.t -> unit Or_error.t)
  -> Args.Standard_with_files.t
  -> unit
(** [lift_command_with_files ?compiler_predicate ?machine_predicate
   ?sanitiser_passes ?with_compiler_tests ~f args] behaves like
    {{!lift_command}lift_command}, but also handles (and supplies)
    optional input and output files. *)

(** {2 Single-file pipelines}

    These are the common pipelines that most of the single-file commands
    are built upon. *)

val explain_pipeline
  :  Compiler.Target.t
  -> (module
      Filter.S with type aux_i =
                      ( File_type.t_or_infer
                        * ( C.Filters.Output.t Filter.chain_output
                            ->
                            Asm_job.Explain_config.t
                              Asm_job.t
                              Compiler.Chain_input.t
                          )
                      )
                and type aux_o =
                      ( C.Filters.Output.t option
                        * ( unit option * Asm_job.output )
                      )
    ) Or_error.t
(** [explain_pipeline target] builds a delitmusify-compile-explain
    pipeline for target [target]. *)

val litmusify_pipeline
  :  Compiler.Target.t
  -> (module
      Filter.S with type aux_i =
                      ( File_type.t_or_infer
                        * ( C.Filters.Output.t Filter.chain_output
                            ->
                            Asm_job.Litmus_config.t
                              Asm_job.t
                              Compiler.Chain_input.t
                          )
                      )
                and type aux_o =
                      ( C.Filters.Output.t option
                        * ( unit option * Asm_job.output )
                      )
    ) Or_error.t
(** [litmusify_pipeline target] builds a delitmusify-compile-litmusify
    pipeline for target [target]. *)

val make_compiler_input
  :  Output.t
  -> File_type.t_or_infer
  -> string list option
  -> 'cfg
  -> Sanitiser_pass.Set.t
  -> C.Filters.Output.t Filter.chain_output
  -> 'cfg Asm_job.t Compiler.Chain_input.t
(** [make_compiler_input o file_type user_cvars cfg passes dl_output]
    generates the input to the compiler stage of a single-file pipeline.

    It takes the original file type [file_type]; the user-supplied C
    variables [user_cvars]; the litmusifier configuration [config];
    the sanitiser passes [passes]; and the output from the de-litmus
    stage of the litmus pipeline [dl_output], which contains any
    postcondition and discovered C variables. *)