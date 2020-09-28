(* The Automagic Compiler Tormentor

   Copyright (c) 2018, 2019, 2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Actions that introduce, or rearrange, for loops. *)

open Import

(** {1 Payloads} *)
module Payload : sig
  module Counter : sig
    (** Type of loop counters in payloads. *)
    type t = {var: Common.Litmus_id.t; ty: Fir.Type.t} [@@deriving sexp]
  end

  module Simple : sig
    (** Type of payloads for simple for-loop actions. *)
    type t = {lc: Counter.t; up_to: Fir.Constant.t} [@@deriving sexp]

    (** Shorthand for types of actions that take this payload. *)
    module type S_action =
      Fuzz.Action_types.S with type Payload.t = t Fuzz.Payload_impl.Pathed.t
  end

  module Kv : sig
    (** Type of payloads for known-value for-loop actions. *)
    type t =
      {lc: Counter.t; kv_val: Fir.Constant.t; kv_expr: Fir.Expression.t}
    [@@deriving sexp]

    (** Shorthand for types of actions that take this payload. *)
    module type S_action =
      Fuzz.Action_types.S with type Payload.t = t Fuzz.Payload_impl.Pathed.t
  end
end

(** {2 Insert actions}

    These all insert loops with dead-code bodies, since every other loop can
    be expressed as a surround. *)
module Insert : sig
  (** Action that inserts for-loops guaranteed statically to be dead, by use
      of a known value comparison that will always fail. *)
  module Kv_never : Payload.Kv.S_action
end

(** {2 Surround actions} *)
module Surround : sig
  (** Action that surrounds things with for-loops with a small, constant
      number of iterations. *)
  module Simple : Payload.Simple.S_action

  (** Action that surrounds things with for-loops guaranteed statically to
      evaluate only once, by use of a known value comparison that will only
      hold in the first iteration. *)
  module Kv_once : Payload.Kv.S_action
end