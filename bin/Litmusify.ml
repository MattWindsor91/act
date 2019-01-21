(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation
   files (the "Software"), to deal in the Software without
   restriction, including without limitation the rights to use, copy,
   modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. *)

open Core
open Lib
open Utils

module Post_filter = struct
  module Err = Or_error

  type t =
    [ `Herd
    | `Litmus
    | `None
    ]
  ;;

  type cfg =
    [ `Herd   of Herd.t
    | `Litmus of Litmus_tool.Config.t
    | `None
    ]
  ;;

  (** All post-filters have the same signature. *)
  module type S = Filter.S with type aux_i = cfg and type aux_o = unit

  (** Adapts the Herd filter to try extract its config from a [cfg]. *)
  module Herd_filter : S =
    Filter.Adapt (struct
      module Original = Herd.Filter

      type aux_i = cfg
      type aux_o = unit

      let adapt_i : cfg -> Herd.t Err.t = function
        | `Herd h   -> Err.return h
        | `Litmus _ -> Err.error_string "Expected Herd config, got litmus"
        | `None     -> Err.error_string "Expected Herd config, got none"

      let adapt_o : unit -> unit Err.t = Err.return
    end)

  (** Adapts the Litmus-tool filter to try extract its config from a [cfg]. *)
  module Litmus_filter (R : Runner.S) : S =
    Filter.Adapt (struct
      module Original = Litmus_tool.Filter (R)

      type aux_i = cfg
      type aux_o = unit

      let adapt_i : cfg -> Litmus_tool.Config.t Err.t = function
        | `Litmus l -> Err.return l
        | `Herd _   -> Err.error_string "Expected Litmus config, got herd"
        | `None     -> Err.error_string "Expected Litmus config, got none"

      let adapt_o : unit -> unit Err.t = Err.return
    end)

  (** This mainly exists so that there's still a module returned by
      {{!make}make}, even if we don't need one.

      In practice, {{!chain}chain} makes sure that this filter is
      never run. *)
  module Dummy : S =
    Filter.Make (struct
      type aux_i = cfg
      type aux_o = unit
      let name = "dummy"

      let tmp_file_ext = Fn.const "tmp"

      let run
          (_ : cfg Filter.ctx)
          (_ : In_channel.t)
          (_ : Out_channel.t)
        : unit Err.t =
        Err.error_string
          "Internal error: tried to postprocess litmus with no filter"
    end)

  (** [make mach_runner which] makes a post-filter module based on the
      request [which].  If the post-filter is Litmus, then it is set up
      to run using [mach_runner]; other post-filters are run locally. *)
  let make (module Mach_runner : Runner.S) : t -> (module S) = function
    | `Herd   -> (module Herd_filter)
    | `Litmus -> (module Litmus_filter (Mach_runner))
    | `None   -> (module Dummy)
  ;;

  let chain
      (type i)
      (type o)
      (filter : t)
      (module R : Runner.S)
      (module M : Filter.S with type aux_i = i and type aux_o = o)
    : ( module
        Filter.S with type aux_i = (i * cfg)
                  and type aux_o = (o * unit option)
      ) =
    let (module Post) = make (module R) filter in
    (module
      Filter.Chain_conditional_second (struct
        type aux_i_combi = (i * cfg)

        let select { Filter.aux = (rest, cfg); _ } =
          match cfg with
          | `None -> `One rest
          | `Herd _ | `Litmus _ -> `Both (rest, cfg)
        module First = M
        module Second = Post
      end))

  let herd_config (cfg : Config.M.t) (target : Common.target)
    : Herd.t Err.t =
    let open Err.Let_syntax in
    let%bind herd_cfg = Config.M.require_herd cfg in
    let arch = Herd.Assembly (Common.arch_of_target target) in
    Herd.create ~config:herd_cfg ~arch
  ;;

  let machine_of_target (cfg : Config.M.t)
    : Common.target -> Machine.Spec.With_id.t Err.t = function
    | `Spec s -> Err.return (Compiler.Spec.With_id.machine s)
    | `Arch _ ->
      (* TODO(@MattWindsor91): should really check that the machine
         has the right architecture! *)
      Machine.Spec.Set.get (Config.M.machines cfg) Machine.Id.default
  ;;

  let litmus_config
      (cfg : Config.M.t)
      (target : Common.target)
    : Litmus_tool.Config.t Err.t =
    let open Err.Let_syntax in
    let%bind machine = machine_of_target cfg target in
    Err.tag_arg
      (Travesty.T_option.one (Machine.Spec.With_id.litmus machine))
      "While trying to find litmus config for machine"
      (Machine.Spec.With_id.id machine)
      [%sexp_of: Machine.Id.t]
  ;;

  let make_config
      (cfg    : Config.M.t)
      (target : Common.target)
    : t -> cfg Err.t = function
    | `Herd   -> Err.(herd_config   cfg target >>| fun h -> `Herd   h)
    | `Litmus -> Err.(litmus_config cfg target >>| fun l -> `Litmus l)
    | `None   -> Err.return `None
end

let make_filter
  (post_filter : Post_filter.t)
  (target : Common.target)
  (target_runner : (module Runner.S))
  : ( module
      Filter.S with type aux_i =
                      ( ( Common.file_type
                          * ( Common.file_type
                              * Asm_job.Litmus_config.t Asm_job.t
                            )
                        )
                        * Post_filter.cfg
                      )
                and type aux_o =
                      ( ( C.Filters.Output.t option
                          * ( unit option
                              * Asm_job.output
                            )
                        )
                        * unit option
                      )
    ) Or_error.t =
  let open Or_error in
  Common.(
    target
    |>  asm_runner_of_target
    >>| Asm_job.get_litmusify
    >>= chain_with_compiler target
    >>| chain_with_delitmus
    >>| Post_filter.chain post_filter target_runner
  )
;;

let run file_type (filter : Post_filter.t) compiler_id_or_emits
    (c_symbols : string list)
    (post_sexp : [ `Exists of Sexp.t ] option)
    ~(infile_raw : string option)
    ~(outfile_raw : string option) o cfg =
  Common.warn_if_not_tracking_symbols o c_symbols;
  let open Result.Let_syntax in
  let%bind target = Common.get_target cfg compiler_id_or_emits in
  let%bind tgt_machine = Post_filter.machine_of_target cfg target in
  let tgt_runner = Machine.Spec.With_id.runner tgt_machine in
  let passes =
    Config.M.sanitiser_passes cfg ~default:Sanitiser_pass.standard
  in
  let config = Asm_job.Litmus_config.make ?post_sexp () in
  let litmus_job = Asm_job.make ~passes ~config ~symbols:c_symbols () in
  let%bind (module Flt) = make_filter filter target tgt_runner in
  let%bind pf_cfg = Post_filter.make_config cfg target filter in
  let inner_file_type =
    match file_type with
    | `C_litmus -> `C
    | x         -> x
  in
  let%map _ =
    Flt.run_from_string_paths
      ((file_type, (inner_file_type, litmus_job)), pf_cfg)
      ~infile:infile_raw ~outfile:outfile_raw in
  ()
;;

let command =
  let open Command.Let_syntax in
  Command.basic
    ~summary:"converts an assembly file to a litmus test"
    [%map_open
      let standard_args = Standard_args.get
      and sanitiser_passes = Standard_args.Other.sanitiser_passes
      and filter = Standard_args.Other.(
          choose_one
            [ flag_to_enum_choice `Herd "herd"
                ~doc:"pipe results through `herd`"
            ; flag_to_enum_choice `Litmus "litmus"
                ~doc:"pipe results through `litmus`"
            ]
            ~if_nothing_chosen:(`Default_to `None)
        )
      and file_type = Standard_args.Other.file_type
      and compiler_id_or_arch = Standard_args.Other.compiler_id_or_arch
      and c_symbols = Standard_args.Other.c_symbols
      and post_sexp =
        choose_one
          [ map ~f:(Option.map ~f:(fun x -> Some (`Exists x)))
              (flag "exists"
                 (* We can't actually type-check the postcondition until we
                    have a target language! *)
                 (optional sexp)
                 ~doc: "PREDICATE an 'exists' postcondition to attach to the resulting Litmus test")
          ]
          ~if_nothing_chosen:(`Default_to None)
      and outfile_raw =
        flag "output"
          (optional file)
          ~doc: "FILE the litmus output file (default: stdout)"
      and infile_raw = anon (maybe ("FILE" %: file)) in
      fun () ->
        Common.lift_command standard_args
          ?sanitiser_passes
          ~with_compiler_tests:false
          ~f:(run
                file_type filter compiler_id_or_arch c_symbols
                post_sexp
                ~infile_raw ~outfile_raw)
    ]
