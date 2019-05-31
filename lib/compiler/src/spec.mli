(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Compiler specifications. *)

include Spec_types.S

val make :
     ?argv:string list
  -> enabled:bool
  -> style:Act_common.Id.t
  -> emits:Act_common.Id.t
  -> cmd:string
  -> unit
  -> t
(** [make ?argv ~enabled ~style ~emits ~cmd ()] creates a compiler spec with
    the given fields. *)

(** We extend [With_id] to include all of the accessors from [Basic_spec]. *)
module With_id : sig
  include Act_common.Spec_types.S_with_id with type elt := t

  include Spec_types.S with type t := t
end

include Act_common.Spec.S with type t := t and module With_id := With_id
