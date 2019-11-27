(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Stock payloads, helpers for building payloads, and so on.

    See {!Action_types.S_payload} for the shape of an action payload. *)

open Base

(** {1 Helpers for building action payloads} *)

module Helpers : sig
  val lift_quickcheck :
       'a Base_quickcheck.Generator.t
    -> random:Splittable_random.State.t
    -> 'a State.Monad.t
  (** [lift_quickcheck gen ~random] lifts a Quickcheck-style generator [gen]
      into a state-monad action taking a random number generator [random] and
      outputting the randomly generated value. *)

  val lift_quickcheck_opt :
       'a Base_quickcheck.Generator.t option
    -> random:Splittable_random.State.t
    -> 'a State.Monad.t
  (** [lift_quickcheck_opt gen_opt ~random] behaves as {!lift_quickcheck} if
      [gen_opt] is [Some gen], and emits an error inside the state monad if
      not. *)
end

(** {1 Stock payloads and functors for building them} *)

module None : Action_types.S_payload with type t = unit
(** Dummy payload module for actions that take no payload. *)

(** Adapts payload generators that don't depend on the state of the program. *)
module Pure (S : sig
  type t [@@deriving sexp]

  val quickcheck_generator : t Base_quickcheck.Generator.t
end) : Action_types.S_payload with type t = S.t

(** Scaffolding for building payload generators that just build program
    paths. *)
module Program_path (S : sig
  val build_filter : Path_filter.t -> Path_filter.t
  (** [build_filter flt] should apply the path filter predicates needed for
      the payload generator to [flt]. *)

  val gen :
       Subject.Test.t
    -> filter:Path_filter.t
    -> Path.program Base_quickcheck.Generator.t option
  (** [gen] should be a path shape generator. *)
end) : Action_types.S_payload with type t = Path.program

(** {2 Surround} *)

(* Payload for actions that surround a statement span with an if- or
   do-while- construct.

   The payload for any surround action contains two elements:

   - the expression to insert into the condition of the if statement; - the
   path to the statements to remove, pass through the if statement block
   generators, and replace with the statement. *)
module Surround : sig
  type t
  (** Opaque type of payloads. *)

  (** {3 Constructors} *)

  val make : cond:Act_c_mini.Expression.t -> path:Path.program -> t
  (** [make ~cond ~path] makes a payload given a specific condition
      expression [cond] and statement-list selecting path [path]. *)

  (** {3 Accessors} *)

  val cond : t -> Act_c_mini.Expression.t
  (** [cond payload] retrieves the generated condition inside [payload]. *)

  val path : t -> Path.program
  (** [path payload] retrieves the generated path inside [payload]. *)

  val apply :
       t
    -> test:Subject.Test.t
    -> f:
         (   Act_c_mini.Expression.t
          -> Subject.Statement.t list
          -> Subject.Statement.t)
    -> Subject.Test.t State.Monad.t
  (** [apply payload ~test ~f] lifts a surrounding function [f] over a
      payload [payload], supplying the test [test] to transform, and lifting
      the computation into the fuzzer state monad. *)

  (** {3 Using as a payload module} *)

  (** [Make] builds a fully-functional payload module with the surround
      payload and a generator that uses the given conditional generator. *)
  module Make (Basic : sig
    val cond_gen :
         (module Act_c_mini.Env_types.S_with_known_values)
      -> Act_c_mini.Expression.t Base_quickcheck.Generator.t
    (** [cond_gen env] should, given a first-class environment module [env]
        capturing the variables in scope at the point where the if statement
        is appearing, return a Quickcheck generator generating expressions
        over those variables. *)
  end) : Action_types.S_payload with type t = t
end