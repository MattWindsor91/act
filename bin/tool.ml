(* This file is part of 'act'.

   Copyright (c) 2018, 2019 by Matt Windsor

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation
   files (the "Software"), to deal in the Software without
   restriction, including without limitation the rights to use, copy,
   modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. *)

open Core
open Lib

let run_herd ?(argv = []) (_o : Output.t) (cfg : Config.M.t)
  : unit Or_error.t =
  let open Or_error.Let_syntax in
  let%bind herd = Config.M.require_herd cfg in
  Utils.Run.Local.run ~oc:stdout ~prog:herd.cmd argv
;;

let herd_command : Command.t =
  let open Command.Let_syntax in
  Command.basic
    ~summary:"runs Herd with the configured models"
    [%map_open
      let standard_args = Standard_args.get
      and argv = flag "--" Command.Flag.escape ~doc:"STRINGS Arguments to send to Herd directly." in
      fun () ->
        Common.lift_command standard_args
          ~with_compiler_tests:false
          ~f:(run_herd ?argv)
    ]
;;

let command : Command.t =
  Command.group
    ~summary:"Run act tools directly"
    [ "herd", herd_command
    ]
;;