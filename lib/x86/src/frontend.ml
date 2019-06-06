(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

   Permission is hereby granted, free of charge, to any person obtaining a
   copy of this software and associated documentation files (the
   "Software"), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to permit
   persons to whom the Software is furnished to do so, subject to the
   following conditions:

   The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
   NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
   OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
   USE OR OTHER DEALINGS IN THE SOFTWARE. *)

open Base
open Act_common

module type S = Act_utils.Loadable_intf.S with type t = Ast.t

module Att : S = Act_utils.Frontend.Make (struct
  type ast = Ast.t

  module I = Att_parser.MenhirInterpreter

  let lex = Att_lexer.token

  let parse = Att_parser.Incremental.main

  let message = Att_messages.message
end)

let dialect_table : (Id.t, (module S)) List.Assoc.t Lazy.t =
  lazy [(Id.of_string "att", (module Att))]

let of_dialect : Id.t -> (module S) Or_error.t =
  Staged.unstage
    (Dialect.find_by_id dialect_table ~context:"parsing frontend")