(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

   Permission is hereby granted, free of charge, to any person obtaining a
   copy of this software and associated documentation files (the "Software"),
   to deal in the Software without restriction, including without limitation
   the rights to use, copy, modify, merge, publish, distribute, sublicense,
   and/or sell copies of the Software, and to permit persons to whom the
   Software is furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
   DEALINGS IN THE SOFTWARE. *)

(** Signatures for {{!Inherit} Inherit}. *)

(** [S] describes a parent type [t], a component type [c], and a function
    [component] for getting the [c] of a [t]. *)
module type S = sig
  (** The main type. *)
  type t

  (** Type of inner components. *)
  type c

  val component : t -> c
  (** [component x] gets the [c]-typed component of [x]. *)
end

(** [S_partial] describes a parent type [t], an optional component type [c],
    and a function [component_opt] for getting the [c] of a [t], if one
    exists. *)
module type S_partial = sig
  (** The main type. *)
  type t

  (** Type of inner components. *)
  type c

  val component_opt : t -> c option
  (** [component_opt x] tries to get the [c]-typed component of [x]. *)
end
