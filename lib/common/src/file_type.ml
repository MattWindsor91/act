(* This file is part of 'act'.

   Copyright (c) 2018, 2019 by Matt Windsor

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

type t = Asm | Asm_litmus | C | C_litmus | Infer [@@deriving sexp]

let file_type_is (src : Plumbing.Input.t) (expected : string) : bool =
  Option.exists (Plumbing.Input.file_type src) ~f:(String.equal expected)

let is_c (src : Plumbing.Input.t) : t -> bool = function
  | C ->
      true
  | Infer ->
      file_type_is src "c"
  | Asm | Asm_litmus | C_litmus ->
      false

let is_c_litmus (src : Plumbing.Input.t) : t -> bool = function
  | C_litmus ->
      true
  | Infer ->
      file_type_is src "c.litmus"
  | Asm | Asm_litmus | C ->
      false

let is_asm (src : Plumbing.Input.t) : t -> bool = function
  | Asm ->
      true
  | Infer ->
      file_type_is src "s" || file_type_is src "asm"
  | C | Asm_litmus | C_litmus ->
      false

let is_asm_litmus (src : Plumbing.Input.t) : t -> bool = function
  | Asm_litmus ->
      true
  | Infer ->
      file_type_is src "s.litmus" || file_type_is src "asm.litmus"
  | Asm | C_litmus | C ->
      false

let delitmusified : t -> t = function
  | C_litmus ->
      C
  | Asm_litmus ->
      Asm
  | (Asm | C | Infer) as x ->
      x
