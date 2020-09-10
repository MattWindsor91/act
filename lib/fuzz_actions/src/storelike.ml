(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
open Import

let readme_faw : string Lazy.t =
  lazy
    (Printf.sprintf
       {|
    If '%s' is true, this action will only store
    to variables that haven't previously been selected for store actions.
    This makes calculating candidate executions easier, but limits the degree
    of entropy somewhat.  (Note that if the value is stochastic, the action
    will only fire if such variables exist, but may or may not proceed to
    select a previously-stored variable.  This is a limitation of the flag
    system.)
  |}
       (Common.Id.to_string Fuzz.Config_tables.forbid_already_written_flag))

(** Lists the restrictions we put on source variables. *)
let basic_src_restrictions : (Fuzz.Var.Record.t -> bool) list Lazy.t =
  lazy []

module Dst_restriction = struct
  type t = Fuzz.Var.Record.t -> bool

  let basic (dst_type : Fir.Type.Basic.t) : t list =
    let bt =
      Accessor.(Fuzz.Var.Record.Access.type_of @> Fir.Type.Access.basic_type)
    in
    [Fir.Type.Basic.eq bt ~to_:dst_type]

  let with_user_flags ~(dst_type : Fir.Type.Basic.t)
      ~(forbid_already_written : bool) : t list =
    basic dst_type
    @ List.filter_opt
        [ Option.some_if forbid_already_written
            (Fn.non Fuzz.Var.Record.has_writes) ]

  let forbid_dependencies : t =
    Tx.Fn.(
      Fn.non Fuzz.Var.Record.has_dependencies
      (* We don't know whether variables that existed before fuzzing have any
         dependencies, as we don't do any flow analysis of them. Maybe one
         day this will be relaxed? *)
      &&& Fuzz.Var.Record.was_generated)
end

module Make (B : sig
  val name : Common.Id.t
  (** [name] is the name of the action. *)

  val readme_preamble : string list
  (** [readme_preamble] is the part of the action readme specific to this
      form of the storelike action. *)

  val dst_type : Fir.Type.Basic.t
  (** [dst_type] is the value type of the destination. *)

  val path_filter : Fuzz.Path_filter.t
  (** [path_filter] is the filter to apply on statement insertion paths
      before considering them for the atomic store. *)

  val extra_dst_restrictions : Dst_restriction.t list
  (** [extra_dst_restrictions] is a list of additional restrictions to place
      on the destination variables (for example, 'must not have
      dependencies'). *)

  module Flags : Storelike_types.Flags

  include Storelike_types.Basic
end) :
  Fuzz.Action_types.S with type Payload.t = B.t Fuzz.Payload_impl.Insertion.t =
struct
  let name = B.name

  (** [readme_chunks ()] generates fragments of unformatted README text based
      on the configuration of this store module. *)
  let readme_chunks () : string list =
    B.readme_preamble
    @ [ Printf.sprintf "This operation generates '%s's."
          (Fir.Type.Basic.to_string B.dst_type)
      ; Lazy.force readme_faw ]

  let readme () =
    readme_chunks () |> String.concat ~sep:"\n\n"
    |> Act_utils.My_string.format_for_readme

  let src_env (vars : Fuzz.Var.Map.t) ~(tid : int) : Fir.Env.t =
    let predicates = Lazy.force basic_src_restrictions in
    Fuzz.Var.Map.env_satisfying_all ~predicates ~scope:(Local tid) vars

  let dst_restrictions ~(forbid_already_written : bool) :
      (Fuzz.Var.Record.t -> bool) list =
    Dst_restriction.with_user_flags ~dst_type:B.dst_type
      ~forbid_already_written
    @ B.extra_dst_restrictions

  let dst_env (vars : Fuzz.Var.Map.t) ~(tid : int)
      ~(forbid_already_written : bool) : Fir.Env.t =
    let predicates = dst_restrictions ~forbid_already_written in
    Fuzz.Var.Map.env_satisfying_all ~predicates ~scope:(Local tid) vars

  let approx_forbid_already_written (ctx : Fuzz.Availability.Context.t) :
      bool Or_error.t =
    (* If the flag is stochastic, then we can't tell whether its value will
       be the same in the payload check. As such, we need to be pessimistic
       and assume that we _can't_ make writes to already-written variables if
       we can't guarantee an exact value.

       See https://github.com/MattWindsor91/act/issues/172. *)
    Or_error.(
      Fuzz.Param_map.get_flag
        (Fuzz.Availability.Context.param_map ctx)
        ~id:Fuzz.Config_tables.forbid_already_written_flag
      >>| Fuzz.Flag.to_exact_opt
      >>| Option.value ~default:true)

  let path_filter ctx =
    let forbid_already_written =
      ctx |> approx_forbid_already_written |> Result.ok
      |> Option.value ~default:true
    in
    Fuzz.Availability.in_thread_with_variables ctx
      ~predicates:(dst_restrictions ~forbid_already_written)
    @@ Fuzz.Availability.in_thread_with_variables ctx
         ~predicates:(Lazy.force basic_src_restrictions)
    @@ B.path_filter

  module Payload = Fuzz.Payload_impl.Insertion.Make (struct
    type t = B.t [@@deriving sexp]

    let path_filter = path_filter

    module G = Base_quickcheck.Generator

    let error_if_empty (env_name : string) (env : Fir.Env.t) :
        unit Or_error.t =
      Tx.Or_error.when_m (Map.is_empty env) ~f:(fun () ->
          Or_error.error_s
            [%message
              "Internal error: Environment was empty." ~here:[%here]
                ~env_name])

    let check_envs (src : Fir.Env.t) (dst : Fir.Env.t) : unit Or_error.t =
      Or_error.combine_errors_unit
        [error_if_empty "src" src; error_if_empty "dst" dst]

    let is_dependency_cycle_free (pld : t) : bool =
      (* TODO(@MattWindsor91): this is very heavy-handed; we should permit
         references to the destination in the source wherever they are not
         depended-upon, but how do we do this? *)
      let dsts = B.dst_ids pld in
      let srcs = B.src_exprs pld in
      Fir.(
        Accessor.(
          for_all (List.each @> Expression_traverse.depended_upon_idents))
          ~f:(fun id ->
            Option.is_none (List.find dsts ~f:(Common.C_id.equal id))))
        srcs

    let gen' (vars : Fuzz.Var.Map.t) ~(where : Fuzz.Path.t)
        ~(forbid_already_written : bool) : t Fuzz.Opt_gen.t =
      let tid = Fuzz.Path.tid where in
      let src = src_env vars ~tid in
      let dst = dst_env vars ~tid ~forbid_already_written in
      Or_error.Let_syntax.(
        let%map () = check_envs src dst in
        Base_quickcheck.Generator.filter
          (B.gen ~src ~dst ~vars ~tid)
          ~f:is_dependency_cycle_free)

    let gen (wheref : Fuzz.Path.Flagged.t) : t Fuzz.Payload_gen.t =
      Fuzz.Payload_gen.(
        let* forbid_already_written =
          flag Fuzz.Config_tables.forbid_already_written_flag
        in
        let* vars = vars in
        let where = Fuzz.Path_flag.Flagged.path wheref in
        lift_opt_gen (gen' vars ~where ~forbid_already_written))
  end)

  let available : Fuzz.Availability.t =
    (* The path filter requires the path to be in a thread that has access to
       variables satisfying both source and destination restrictions, so we
       need not specify those restrictions separately. *)
    Fuzz.Availability.(
      M.(lift path_filter >>= is_filter_constructible ~kind:Insert))

  let bookkeep_dst (x : Common.C_id.t) ~(tid : int) : unit Fuzz.State.Monad.t
      =
    Fuzz.State.Monad.(
      Let_syntax.(
        let%bind dst_var = resolve x ~scope:(Local tid) in
        let%bind () = add_write dst_var in
        when_m B.Flags.erase_known_values ~f:(fun () ->
            erase_var_value dst_var)))

  let bookkeep_dsts (xs : Common.C_id.t list) ~(tid : int) :
      unit Fuzz.State.Monad.t =
    xs |> List.map ~f:(bookkeep_dst ~tid) |> Fuzz.State.Monad.all_unit

  module MList = Tx.List.On_monad (Fuzz.State.Monad)

  let bookkeep_new_locals (nls : Fir.Initialiser.t Common.C_named.Alist.t)
      ~(tid : int) : unit Fuzz.State.Monad.t =
    MList.iter_m nls ~f:(fun (name, init) ->
        Fuzz.State.Monad.register_var (Common.Litmus_id.local tid name) init)

  let do_bookkeeping (item : B.t) ~(path : Fuzz.Path.Flagged.t) :
      unit Fuzz.State.Monad.t =
    let tid = path |> Fuzz.Path_flag.Flagged.path |> Fuzz.Path.tid in
    Fuzz.State.Monad.(
      Let_syntax.(
        let%bind () = bookkeep_new_locals ~tid (B.new_locals item) in
        let%bind () = bookkeep_dsts ~tid (B.dst_ids item) in
        add_expression_dependencies_at_path ~path (B.src_exprs item)))

  let insert_vars (target : Fuzz.Subject.Test.t)
      (new_locals : Fir.Initialiser.t Common.C_named.Alist.t) ~(tid : int) :
      Fuzz.Subject.Test.t Or_error.t =
    Tx.List.With_errors.fold_m new_locals ~init:target
      ~f:(fun subject (id, init) ->
        Fuzz.Subject.Test.declare_var subject
          (Common.Litmus_id.local tid id)
          init)

  let do_insertions (target : Fuzz.Subject.Test.t)
      ~(path : Fuzz.Path.Flagged.t) ~(to_insert : B.t) :
      Fuzz.Subject.Test.t Or_error.t =
    let tid = Fuzz.Path.tid (Fuzz.Path_flag.Flagged.path path) in
    let stms =
      to_insert |> B.to_stms
      |> List.map ~f:Fuzz.Subject.Statement.make_generated_prim
    in
    Or_error.Let_syntax.(
      let%bind target' =
        Fuzz.Path_consumers.consume_with_flags target ~filter:B.path_filter
          ~path ~action:(Insert stms)
      in
      insert_vars target' (B.new_locals to_insert) ~tid)

  let run (subject : Fuzz.Subject.Test.t)
      ~(payload : B.t Fuzz.Payload_impl.Insertion.t) :
      Fuzz.Subject.Test.t Fuzz.State.Monad.t =
    let to_insert = Fuzz.Payload_impl.Insertion.to_insert payload in
    let path = Fuzz.Payload_impl.Insertion.where payload in
    Fuzz.State.Monad.(
      Let_syntax.(
        let%bind () = do_bookkeeping to_insert ~path in
        Monadic.return (do_insertions subject ~path ~to_insert)))
end
