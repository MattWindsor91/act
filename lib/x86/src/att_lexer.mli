(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2019 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Lexing X86 assembly *)

val token : Sedlexing.lexbuf -> Att_parser.token
(** [token lexbuf] is a Sedlex lexer for AT&T-dialect x86. *)