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

(** Opaque type of variable maps. *)
type t [@@deriving equal]

(** {2 Constructors} *)

val empty : t
(** [empty] is the empty variable map. *)

val of_map : Act_common.C_id.t option Map.M(Act_common.Litmus_id).t -> t
(** [of_map map] creates a variable map from a [Base]-style map between
    Litmus variables and their optional global-scope C variable forms
    post-delitmus. *)

val of_set_with_qualifier :
     Set.M(Act_common.Litmus_id).t
  -> qualifier:(Act_common.Litmus_id.t -> Act_common.C_id.t option)
  -> t
(** [of_set_with_qualifier set ~qualifier] creates a variable map by
    applying [qualifier] to each Litmus variable in [set]. *)

(** {2 Projections} *)

val globally_mapped_litmus_ids : t -> Set.M(Act_common.Litmus_id).t
(** [globally_mapped_litmus_ids map] gets the set of litmus IDs that the delitmusifier
    mapped to global C variables in [map]. *)

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

(** A var map can be serialised to, and deserialised from, (Yo)JSON. *)
include Plumbing.Loadable_types.Jsonable with type t := t
