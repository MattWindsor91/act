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

open Base

(** [Basic] contains all the various modules and components needed to run
    tests on one compiler. *)
module type Basic = sig
  include Common_intf.Basic

  (** The compiler interface for this compiler. *)
  module C : Act_compiler.Instance_types.S

  (** A runner for performing tasks on the assembly generated by [C]. *)
  module R : Act_asm.Runner_intf.Basic

  (** The simulator runner for simulating assembly Litmus tests on this
      compiler. *)
  module Asm_simulator : Act_sim.Runner_intf.S

  val ps : Pathset.Compiler.t
  (** [ps] tells the tester where it can find input files, and where it
      should put output files, for this compiler. *)

  val spec : Act_compiler.Spec.With_id.t
  (** [spec] is the compiler's ID-tagged specification. *)
end

(** User-facing interface for running compiler tests on a single compiler. *)
module type S = sig
  val run : Act_sim.Bulk.File_map.t -> Analysis.Compiler.t Or_error.t
  (** [run c_sims] runs tests on each file in the module's pathset, given
      the output of running C simulations in [c_sims], and returning a
      compiler-level analysis. *)
end