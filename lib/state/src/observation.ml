(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

open Base
open Base_quickcheck

module Entry_tag = struct
  type t = Witness | Counter_example | Unknown

  let process (witnesses : Set.M(Entry).t)
      (counter_examples : Set.M(Entry).t) (tag : t)
      ~(entries : Set.M(Entry).t) : Set.M(Entry).t * Set.M(Entry).t =
    match tag with
    | Witness ->
        (Set.union witnesses entries, counter_examples)
    | Counter_example ->
        (witnesses, Set.union counter_examples entries)
    | Unknown ->
        (witnesses, counter_examples)
end

module Flag = struct
  module M = struct
    type t = Sat | Unsat | Undefined [@@deriving enum, quickcheck]

    let table : (t, string) List.Assoc.t =
      [(Sat, "sat"); (Unsat, "unsat"); (Undefined, "undef")]
  end

  include M
  include Act_utils.Enum.Extend_table (M)
end

(* This weird module is necessary to set up the deriving magic for sexp_of
   and quickcheck later on, because if we use Set.M(Flag).t directly we
   can't derive quickcheck, and if we use Set.t directly we can't derive
   sexp_of. *)
module Flag_set = struct
  type t = Set.M(Flag).t [@@deriving sexp_of]

  let quickcheck_generator : t Generator.t =
    Generator.set_t_m (module Flag) Flag.quickcheck_generator

  let quickcheck_shrinker : t Shrinker.t =
    Shrinker.set_t Flag.quickcheck_shrinker

  let quickcheck_observer : t Observer.t =
    Observer.set_t Flag.quickcheck_observer

  module Json = Plumbing.Jsonable.Set.Make (Flag)

  include (Json : module type of Json with type t := t)
end

module M = struct
  type t =
    { flags: Flag_set.t
    ; states: Entry.Set.t
    ; witnesses: Entry.Set.t
    ; counter_examples: Entry.Set.t }
  [@@deriving fields, sexp_of, quickcheck, yojson]
end

include M
include Plumbing.Loadable.Of_jsonable (M)
include Plumbing.Storable.Of_jsonable (M)

let has_flag (x : t) ~(flag : Flag.t) : bool = Set.mem (flags x) flag

let is_undefined : t -> bool = has_flag ~flag:Undefined

let is_unsat : t -> bool = has_flag ~flag:Sat

let is_sat : t -> bool = has_flag ~flag:Unsat

let empty : t =
  { flags= Set.empty (module Flag)
  ; states= Set.empty (module Entry)
  ; witnesses= Set.empty (module Entry)
  ; counter_examples= Set.empty (module Entry) }

let add_many_raw ?(tag : Entry_tag.t = Entry_tag.Unknown) (obs : t)
    ~(entries : Set.M(Entry).t) : t =
  let witnesses = witnesses obs in
  let counter_examples = counter_examples obs in
  let states' = Set.union entries (states obs) in
  let witnesses', counter_examples' =
    Entry_tag.process witnesses counter_examples tag ~entries
  in
  { obs with
    states= states'
  ; witnesses= witnesses'
  ; counter_examples= counter_examples' }

let add_many ?(tag : Entry_tag.t option) (obs : t)
    ~(entries : Set.M(Entry).t) : t Or_error.t =
  (* TODO(@MattWindsor91): it's unclear as to whether this treatment of
     'undefined' is correct. *)
  if is_undefined obs then
    Or_error.error_s
      [%message
        "Can't add state(s) to observation, as the output is marked \
         undefined"
          (entries : Set.M(Entry).t)]
  else Or_error.return (add_many_raw ?tag obs ~entries)

let add ?(tag : Entry_tag.t option) (obs : t) ~(entry : Entry.t) :
    t Or_error.t =
  add_many ?tag obs ~entries:(Set.singleton (module Entry) entry)

let set_flag_raw (obs : t) ~(flag : Flag.t) : t =
  {obs with flags= Set.add obs.flags flag}

let set_flag (obs : t) ~(flag : Flag.t) : t Or_error.t =
  if has_flag obs ~flag then
    Or_error.errorf "Observation is already marked %s" (Flag.to_string flag)
  else Or_error.return (set_flag_raw obs ~flag)

let set_undefined (obs : t) : t Or_error.t =
  if not (Set.is_empty (states obs)) then
    Or_error.error_s
      [%message
        "Can't mark observation as undefined, as it has states"
          (states obs : Set.M(Entry).t)]
  else set_flag obs ~flag:Undefined

let set_unsat : t -> t Or_error.t = set_flag ~flag:Unsat

let set_sat : t -> t Or_error.t = set_flag ~flag:Sat
