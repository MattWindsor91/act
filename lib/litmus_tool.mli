(* This file is part of 'act'.

   Copyright (c) 2018, 2019 by Matt Windsor

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

(** Interaction with the 'Litmus' tool.

    This is the tool that supports running of Litmus tests on
    real hardware, and not to be confused with the tests itself. *)

open Base
open Utils

module Config : sig
  type t [@@deriving sexp]
  (** The opaque type of Litmus configuration. *)

  include Pretty_printer.S with type t := t

  val create : ?cmd:string -> unit -> t
  (** [create ?cmd] creates a Litmus-tool config. *)
end

val run_direct
  :  ?oc:Stdio.Out_channel.t
  -> Config.t
  -> string list
  -> unit Or_error.t
(** [run_direct ?oc cfg argv] runs Litmus locally, with configuration
    [cfg] and arguments [argv], and outputs its results to [oc]
    (or stdout if [oc] is absent). *)

module Filter : Filter.S with type aux_i = Config.t
                          and type aux_o = unit
(** Interface for running litmus as a filter. *)
