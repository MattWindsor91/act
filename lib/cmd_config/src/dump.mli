(* The Automagic Compiler Tormentor
   Copyright (c) 2018--2020 Matt Windsor and contributors
   - ACT itself is licensed under the MIT License. See the LICENSE file in the
     project root for more information.
   - ACT is based in part on code from the Herdtools7 project
     (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
     project root for more information. *)

(** A command for dumping the current configuration. *)

(** [command] is the dump command. *)
val command : Core_kernel.Command.t
