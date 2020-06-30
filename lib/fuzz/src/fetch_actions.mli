(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Actions that generate fetch statements. *)

(** Shorthand type for fetch actions. *)
module type S =
  Action_types.S
    with type Payload.t =
          Act_fir.Expression.t Act_fir.Atomic_fetch.t Payload.Insertion.t

(* TODO(@MattWindsor91): add Int. *)

(** [Int_dead] is a variant of [Int] that only targets dead-code, and, in
    turn, requires and adds fewer constraints on the destination. *)
module Int_dead : S

(** [Int_redundant] is a variant of [Int] that only fetches with a bias of 0. *)
module Int_redundant : S