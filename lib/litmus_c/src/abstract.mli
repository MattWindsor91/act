(* The Automagic Compiler Tormentor

   Copyright (c) 2018--2020 Matt Windsor and contributors

   ACT itself is licensed under the MIT License. See the LICENSE file in the
   project root for more information.

   ACT is based in part on code from the Herdtools7 project
   (https://github.com/herd/herdtools7) : see the LICENSE.herd file in the
   project root for more information. *)

(** Converting an AST into FIR.

    This module contains partial functions that try to convert a full C AST
    into FIR. They fail if the AST contains pieces of C syntax that aren't
    expressible in FIR. *)

open Base

val sift_decls :
  ([> `Decl of 'd] as 'a) list -> ('d list * 'a list) Or_error.t
(** [sift_decls maybe_decl_list] tries to separate [maybe_decl_list] into a
    list of declarations followed immediately by a list of code, C89-style. *)

val stm : Ast.Stm.t -> unit Act_fir.Statement.t Or_error.t
(** [stm ast] tries to interpret a C statement AST as a FIR statement. *)

val expr : Ast.Expr.t -> Act_fir.Expression.t Or_error.t
(** [expr ast] tries to interpret a C expression AST as a FIR statement. *)

val func :
     Ast.Function_def.t
  -> unit Act_fir.Function.t Act_common.C_named.t Or_error.t
(** [func ast] tries to interpret a C function definition AST as a FIR
    function. *)

val translation_unit :
  Ast.Translation_unit.t -> unit Act_fir.Program.t Or_error.t
(** [translation_unit ast] tries to interpret a C translation unit AST as a
    FIR program. *)

val litmus_post :
     Ast_basic.Constant.t Act_litmus.Postcondition.t
  -> Act_fir.Constant.t Act_litmus.Postcondition.t Or_error.t
(** [litmus_post pc] tries to interpret a Litmus postcondition [pc] over the
    full C AST as one over FIR. *)

val litmus : Ast.Litmus.t -> Act_fir.Litmus.Test.t Or_error.t
(** [litmus test] tries to interpret a Litmus test over the full C AST as one
    over FIR. *)

val litmus_of_raw_ast :
  Act_litmus.Ast.M(Ast.Litmus_lang).t -> Act_fir.Litmus.Test.t Or_error.t
(** [litmus_of_raw_ast test] applies [litmus] to the validated form, if
    available, of [test]. *)