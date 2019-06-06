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
module Au = Act_utils

type t = {vf: Formatter.t; wf: Formatter.t; ef: Formatter.t}

let maybe_err_formatter on : Formatter.t =
  if on then Fmt.stderr else Au.My_format.null_formatter ()

let make ~verbose ~warnings : t =
  { vf= maybe_err_formatter verbose
  ; wf= maybe_err_formatter warnings
  ; ef= Fmt.stderr }

let silent () : t =
  let nullf = Au.My_format.null_formatter () in
  {vf= nullf; wf= nullf; ef= nullf}

let pv (type a) (o : t) : (a, Formatter.t, unit) format -> a = Fmt.pf o.vf

let pw (type a) (o : t) : (a, Formatter.t, unit) format -> a = Fmt.pf o.wf

let pe (type a) (o : t) : (a, Formatter.t, unit) format -> a = Fmt.pf o.ef

module Stage_banner = struct
  let pp_stage : string Fmt.t =
    Fmt.(styled `Magenta (using String.uppercase string))

  let pp_sub_stage : string Fmt.t = Fmt.(parens (styled `Cyan string))

  let pp_id : Id.t Fmt.t = Fmt.(brackets (styled `Blue Id.pp))

  let pp_machine : Id.t Fmt.t =
    Fmt.(prefix (unit "@@@,") (styled `Yellow Id.pp))

  let pp_in_file : string Fmt.t = Fmt.(prefix (unit "@ ") string)

  let pp_out_file : string Fmt.t = Fmt.(prefix (unit "@ ->@ ") string)

  let run ?(id : Id.t option) ?(machine : Id.t option)
      ?(in_file : string option) ?(out_file : string option)
      ?(sub_stage : string option) (o : t) ~(stage : string) : unit =
    Fmt.(
      pv o "@[@[<h>%a@,%a@,%a@,%a@]@,@[<h>%a@]@,@[<h>%a@]@]@." pp_stage
        stage (option pp_sub_stage) sub_stage (option pp_id) id
        (option pp_machine) machine (option pp_in_file) in_file
        (option pp_out_file) out_file)
end

let log_stage = Stage_banner.run

let print_error_body : Error.t Fmt.t =
  Fmt.(
    vbox ~indent:2
      (prefix
         (suffix sp
            (hbox (styled_unit `Red "act encountered a top-level error:")))
         (box Error.pp)))

let print_error (o : t) : 'a Or_error.t -> unit =
  Fmt.(result ~ok:nop ~error:(suffix (Fmt.unit "@.") print_error_body)) o.ef