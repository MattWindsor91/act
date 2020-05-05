(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base

open struct
  module Ac = Act_common
  module Cm = Act_c_mini
  module Tx = Travesty_base_exts
end

module Statement = struct
  type t = Metadata.t Cm.Statement.t [@@deriving sexp]

  module If = struct
    type t = Metadata.t Cm.Statement.If.t [@@deriving sexp]
  end

  module Loop = struct
    type t = Metadata.t Cm.Statement.While.t [@@deriving sexp]
  end

  let has_dead_code_blocks : t -> bool =
    Cm.Statement.has_blocks_with_metadata ~predicate:Metadata.is_dead_code

  include Cm.Statement.With_meta (Metadata)

  let has_atomic_statements : t -> bool =
    On_primitives.exists ~f:Cm.Prim_statement.is_atomic

  let has_labels : t -> bool =
    On_primitives.exists ~f:Cm.Prim_statement.is_label

  let has_non_label_prims : t -> bool =
    On_primitives.exists ~f:(Fn.non Cm.Prim_statement.is_label)

  let make_generated_prim : Cm.Prim_statement.t -> t =
    Cm.Statement.prim Metadata.generated
end

module Block = struct
  type t = (Metadata.t, Statement.t) Cm.Block.t

  let make_existing ?(statements : Statement.t list option) () : t =
    Cm.Block.make ?statements ~metadata:Metadata.existing ()

  let make_generated ?(statements : Statement.t list option) () : t =
    Cm.Block.make ?statements ~metadata:Metadata.generated ()

  let make_dead_code ?(statements : Statement.t list option) () : t =
    Cm.Block.make ?statements ~metadata:Metadata.dead_code ()
end

module Thread = struct
  type t =
    { decls: Cm.Initialiser.t Ac.C_named.Alist.t [@default []]
    ; stms: Statement.t list }
  [@@deriving sexp, make]

  let empty : t = {decls= []; stms= []}

  module An = Ac.C_named.Alist.As_named (Cm.Initialiser)

  let map_decls (thread : t)
      ~(f : Cm.Initialiser.t Ac.C_named.t -> Cm.Initialiser.t Ac.C_named.t) :
      t =
    {thread with decls= An.map ~f thread.decls}

  let add_decl ?(value : Cm.Constant.t option) (thread : t) ~(ty : Cm.Type.t)
      ~(name : Ac.C_id.t) : t =
    let decl = Cm.Initialiser.make ~ty ?value () in
    let decls' = (name, decl) :: thread.decls in
    {thread with decls= decls'}

  let has_statements (p : t) : bool = not (List.is_empty p.stms)

  let has_statements_matching_class (p : t)
      ~(template : Cm.Statement_class.t) : bool =
    List.exists p.stms ~f:(fun x ->
        0 < Cm.Statement_class.count_matches x ~template)

  let has_non_label_prims (p : t) : bool =
    List.exists p.stms ~f:Statement.has_non_label_prims

  let has_dead_code_blocks (p : t) : bool =
    List.exists p.stms ~f:Statement.has_dead_code_blocks

  let statements_of_function (func : unit Cm.Function.t) : Statement.t list =
    func |> Cm.Function.body_stms
    |> List.map
         ~f:(Cm.Statement.On_meta.map ~f:(fun () -> Metadata.existing))

  let of_function (func : unit Cm.Function.t) : t =
    make
      ~decls:(Cm.Function.body_decls func)
      ~stms:(statements_of_function func)
      ()

  module R_alist = Ac.C_named.Alist.As_named (Var.Record)

  (** [make_function_parameters vars] creates a uniform function parameter
      list for a C litmus test using the global variable records in [vars]. *)
  let make_function_parameters (vars : Var.Map.t) :
      Cm.Type.t Ac.C_named.Alist.t =
    vars
    |> Var.Map.env_satisfying_all ~scope:Global ~predicates:[]
    |> Cm.Env.typing |> Map.to_alist

  let to_function (prog : t) ~(vars : Var.Map.t) ~(id : int) :
      unit Cm.Function.t Ac.C_named.t =
    let name = Ac.C_id.of_string (Printf.sprintf "P%d" id) in
    let body_stms = List.map prog.stms ~f:Cm.Statement.erase_meta in
    let parameters = make_function_parameters vars in
    let func =
      Cm.Function.make ~parameters ~body_decls:prog.decls ~body_stms ()
    in
    Ac.C_named.make func ~name

  let list_to_litmus (progs : t list) ~(vars : Var.Map.t) :
      Cm.Litmus.Lang.Program.t list =
    (* We need to filter _before_ we map, since otherwise we'll end up
       assigning the wrong thread IDs. *)
    progs
    |> List.filter ~f:has_statements
    |> List.mapi ~f:(fun id prog -> to_function ~vars ~id prog)
end

module Test = struct
  type t = (Cm.Constant.t, Thread.t) Act_litmus.Test.Raw.t [@@deriving sexp]

  let add_new_thread : t -> t =
    Act_litmus.Test.Raw.add_thread_at_end ~thread:Thread.empty

  let threads_of_litmus (test : Cm.Litmus.Test.t) : Thread.t list =
    test |> Cm.Litmus.Test.threads
    |> List.map ~f:(Fn.compose Thread.of_function Ac.C_named.value)

  let of_litmus (test : Cm.Litmus.Test.t) : t =
    Act_litmus.Test.Raw.make
      ~header:(Cm.Litmus.Test.header test)
      ~threads:(threads_of_litmus test)

  let to_litmus (subject : t) ~(vars : Var.Map.t) :
      Cm.Litmus.Test.t Or_error.t =
    let header = Act_litmus.Test.Raw.header subject in
    let threads = Act_litmus.Test.Raw.threads subject in
    let threads' = Thread.list_to_litmus ~vars threads in
    Cm.Litmus.Test.make ~header ~threads:threads'

  let at_least_one_thread_with (p : t) ~(f : Thread.t -> bool) : bool =
    List.exists (Act_litmus.Test.Raw.threads p) ~f

  let has_statements_matching_class (p : t)
      ~(template : Cm.Statement_class.t) : bool =
    at_least_one_thread_with p
      ~f:(Thread.has_statements_matching_class ~template)

  let has_atomic_statements : t -> bool =
    has_statements_matching_class ~template:(Cm.Statement_class.atomic ())

  let has_while_loops : t -> bool =
    has_statements_matching_class ~template:(Cm.Statement_class.While None)

  let has_if_statements : t -> bool =
    has_statements_matching_class ~template:Cm.Statement_class.If

  let has_statements : t -> bool =
    at_least_one_thread_with ~f:Thread.has_statements

  let has_non_label_prims : t -> bool =
    at_least_one_thread_with ~f:Thread.has_non_label_prims

  let has_dead_code_blocks : t -> bool =
    at_least_one_thread_with ~f:Thread.has_dead_code_blocks

  let add_var_to_init (subject : t) (name : Ac.C_id.t)
      (initial_value : Cm.Constant.t) : t Or_error.t =
    Act_litmus.Test.Raw.try_map_header subject
      ~f:(Act_litmus.Header.add_global ~name ~initial_value)

  let add_var_to_thread (subject : t) (ty : Cm.Type.t) (index : int)
      (name : Ac.C_id.t) (value : Cm.Constant.t) : t Or_error.t =
    Act_litmus.Test.Raw.try_map_thread subject ~index ~f:(fun thread ->
        Ok (Thread.add_decl thread ~ty ~name ~value))

  let declare_var (subject : t) (ty : Cm.Type.t) (var : Ac.Litmus_id.t)
      (initial_value : Cm.Constant.t) : t Or_error.t =
    let name = Ac.Litmus_id.variable_name var in
    match Ac.Litmus_id.tid var with
    | None ->
        add_var_to_init subject name initial_value
    | Some i ->
        add_var_to_thread subject ty i name initial_value
end
