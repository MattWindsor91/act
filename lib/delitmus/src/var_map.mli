(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Post-delitmus variable maps.

    These maps primarily associate Litmus IDs with the global symbols into
    which the delitmusifier has flattened them. *)

open Base

(** {2 Records} *)

module Record : sig
  type t [@@deriving yojson, equal]

  val make :
       c_type:Act_c_mini.Type.t
    -> c_id:Act_common.C_id.t
    -> mapped_to_global:bool
    -> t

  val c_type : t -> Act_c_mini.Type.t
  (** [c_type r] gets the C type of [r]. *)

  val c_id : t -> Act_common.C_id.t
  (** [c_id r] gets the delitmusified C variable name of [r]. *)

  val mapped_to_global : t -> bool
  (** [mapped_to_global r] gets whether [r]'s variable has been mapped into the
      global scope. *)
end

type t = Record.t Act_common.Scoped_map.t [@@deriving equal]
(** Delitmus variable maps are a specific case of scoped map. *)

(** {2 Projections specific to delitmus variable maps} *)

val globally_unmapped_vars :
  t -> (Act_common.Litmus_id.t, Record.t) List.Assoc.t

val globally_mapped_vars :
  t -> (Act_common.Litmus_id.t, Record.t) List.Assoc.t

val global_c_variables : t -> Set.M(Act_common.C_id).t
(** [global_c_variables map] gets the set of global C variables generated by
    the delitmusifier over [map]. *)

val lookup_and_require_global :
  t -> id:Act_common.Litmus_id.t -> Act_common.C_id.t Or_error.t
(** [lookup_and_require_global map ~id] looks up the Litmus ID [id] in the
    var map. It returns [x] if [id] was mapped to a global C variable [id]
    in [map], or an error otherwise (ie, [id] was not mapped to a global C
    variable, or not seen at all). *)

(** {2 Interface implementations} *)

include
  Plumbing.Jsonable_types.S with type t := t
(** A var map can be serialised to, and deserialised from, (Yo)JSON. *)
