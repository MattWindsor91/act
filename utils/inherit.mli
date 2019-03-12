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

(** [Inherit] contains helper signatures for building functors that
    let abstract data types 'inherit' properties of one of their
    components.

    This is based on the pattern used in [Base.Comparable]. *)

(** [S] describes a parent type [t], a component type [c], and a
    function [component] for getting the [c] of a [t]. *)
module type S = sig
  type t
  (** The main type. *)

  type c
  (** Type of inner components. *)

  (** [component x] gets the [c]-typed component of [x]. *)
  val component : t -> c
end

(** [S_partial] describes a parent type [t], an optional component
   type [c], and a function [component_opt] for getting the [c] of a
   [t], if one exists. *)
module type S_partial = sig
  type t
  (** The main type. *)

  type c
  (** Type of inner components. *)

  (** [component_opt x] tries to get the [c]-typed component of [x]. *)
  val component_opt : t -> c option
end

module Make_partial (I : S)
  : S_partial with type t = I.t and type c = I.c
(** [Make_partial] converts an [S] into an [S_partial] that always
    returns [Some (component x)] for [component_opt x]. *)

(** {2 Helpers for building inheritance modules} *)

(** [Helpers] produces helper functions for forwarding through an
    {{!S}S}. *)
module Helpers (I : S) : sig
  val forward : (I.c -> 'a) -> I.t -> 'a
  (** [forward f t] lifts the component accessor [f] over [t]. *)
end

(** [Partial_helpers] produces helper functions for forwarding through
   an {{!S_partial}S_partial}. *)
module Partial_helpers (I : S_partial) : sig
  val forward_bool : (I.c -> bool) -> I.t -> bool
  (** [forward_bool f t] is [false] if [t] doesn't have the required
     component, and [f c] if it does (and that component is [c]). *)

  val forward_bind : (I.c -> 'a option) -> I.t -> 'a option
  (** [forward_bind f t] is [None] if [t] doesn't have the required
     component, and [f c] if it does (and that component is [c]). *)
end