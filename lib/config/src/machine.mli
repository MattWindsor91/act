(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

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

(** [Machine] contains the high-level interface for specifying and
    interacting with machines. *)

open Core_kernel
open Act_common

include module type of Machine_intf

(** [Property] contains a mini-language for querying machine references,
    suitable for use in [Blang]. *)
module Property : sig
  (** [t] is the opaque type of property queries. *)
  type t [@@deriving sexp]

  val id : Id.Property.t -> t
  (** [id] constructs a query over a machine's ID. *)

  val is_remote : t
  (** [is_remote] constructs a query that asks if a machine is known to be
      remote. *)

  val is_local : t
  (** [is_local] constructs a query that asks if a machine is known to be
      local. *)

  val eval : (module Reference with type t = 'r) -> 'r -> t -> bool
  (** [eval R reference property] evaluates [property] over [reference],
      with respect to module [R]. *)

  val eval_b :
    (module Reference with type t = 'r) -> 'r -> t Blang.t -> bool
  (** [eval_b R reference expr] evaluates a [Blang] expression [expr] over
      [reference], with respect to module [R]. *)

  include Property.S with type t := t
end

(** [Ssh] is a module defining SSH configuration. *)
module Ssh : sig
  type t [@@deriving sexp]

  include Pretty_printer.S with type t := t

  val make : ?user:string -> host:string -> copy_dir:string -> unit -> t
  (** [make ?user ~host ~copy_dir ()] builds an [Ssh.t] from the given
      parameters. *)

  val host : t -> string
  (** [host] gets the hostname of the SSH remote. *)

  val user : t -> string option
  (** [user] gets the optional username of the SSH remote. *)

  val copy_dir : t -> string
  (** [copy_dir] gets the remote directory to which we'll be copying work. *)

  (** [To_config] lifts a [t] to an [Ssh.S]. *)
  module To_config (C : sig
    val ssh : t
  end) : Act_utils.Ssh.S
end

(** [Id] is an extension onto base [Id] that lets such items be machine
    references. *)
module Id : sig
  include module type of Id

  include Reference with type t := t
end

(** [Via] enumerates the various methods of reaching a machine. *)
module Via : sig
  (** [t] is the type of a machine-reaching method. *)
  type t = Local | Ssh of Ssh.t [@@deriving sexp]

  val local : t
  (** [local] is a [Via] for a local machine. *)

  val ssh : Ssh.t -> t
  (** [ssh ssh_config] is a [Via] for a SSH connection. *)

  (** [t] can be pretty-printed. *)
  include Pretty_printer.S with type t := t

  val to_runner : t -> (module Plumbing.Runner_types.S)
  (** [to_runner via] builds a runner module for a [via]. *)

  val remoteness : t -> [> `Local | `Remote | `Unknown]
  (** [remoteness via] gets an estimate of whether [via] is remote. *)
end

(** [Spec] is a module for machine specifications. *)
module Spec : sig
  include Basic_spec with type via := Via.t

  val make :
    ?enabled:bool -> ?via:Via.t -> ?litmus:Litmus_tool.t -> unit -> t
  (** [make ?enabled ?via ?litmus ()] creates a machine spec with the given
      fields.

      These fields are subject to change, and as such [make] is an unstable
      API. *)

  (** [With_id] is an extension onto [Spec.With_id] that lets such items be
      machine references, and adds all of the [Spec] accessors. *)
  module With_id : sig
    include Spec.S_with_id with type elt := t

    include Basic_spec with type t := t and type via := Via.t

    include Reference with type t := t
  end

  (** Machine specifications are specifications. *)
  include Spec.S with type t := t and module With_id := With_id
end
