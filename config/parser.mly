(* This file is part of 'act'.

Copyright (c) 2018, 2019 by Matt Windsor

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

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

%token (* delimiters *) LBRACE RBRACE EOF EOL
%token (* main groups *) MACHINE COMPILER FUZZ
%token (* program subgroups *) CPP HERD LITMUS
%token (* common keywords *) ENABLED CMD ARGV DEFAULT
%token (* fuzz-specific keywords *) ACTION WEIGHT
%token (* Herd-specific keywords *) ASM_MODEL C_MODEL
%token (* machine-specific keywords *) VIA SSH HOST USER COPY TO LOCAL
%token (* compiler-specific keywords *) STYLE EMITS

%token <bool>   BOOL
%token <string> STRING
%token <int>    INTEGER
%token <Id.t>   IDENTIFIER

%type <Ast.t> main
%start main

%%

%inline braced(x):
  | xs = delimited(LBRACE, x, RBRACE) { xs }

%inline line_list(x):
  | xs = separated_nonempty_list(EOL, x?) { Base.List.filter_map ~f:Base.Fn.id xs }

%inline stanza(x):
  | xs = braced(line_list(x)) { xs }

simple_stanza(n, x):
  | xs = preceded(n, stanza(x)) { xs }

id_stanza(n, i, x):
  | n; id = i; xs = stanza(x) { (id, xs) }


main:
  | stanzas = line_list(top_stanza); EOF { stanzas }

top_stanza:
  | c = cpp_stanza      {                 Ast.Top.Cpp      c      }
  | f = fuzz_stanza     {                 Ast.Top.Fuzz     f      }
  | h = herd_stanza     {                 Ast.Top.Herd     h      }
  (* Litmus stanzas are machine-specific. *)
  | x = machine_stanza  { let i, m = x in Ast.Top.Machine  (i, m) }
  | x = compiler_stanza { let i, c = x in Ast.Top.Compiler (i, c) }

cpp_stanza:
  | items = simple_stanza(CPP, cpp_item) { items }

cpp_item:
  | b = enabled { Ast.Cpp.Enabled b  }
  | c = cmd     { Ast.Cpp.Cmd     c  }
  | vs = argv   { Ast.Cpp.Argv    vs }

fuzz_stanza:
  | items = simple_stanza(FUZZ, fuzz_item) { items }

fuzz_item:
  | ACTION; action = IDENTIFIER; weight = fuzz_weight? { Ast.Fuzz.Action (action, weight) }

fuzz_weight:
  | WEIGHT; w = INTEGER { w }

litmus_stanza:
  | items = simple_stanza(LITMUS, litmus_item) { items }

litmus_item:
  | c = cmd                               { Ast.Litmus.Cmd c }

herd_stanza:
  | items = simple_stanza(HERD, herd_item) { items }

herd_item:
  | c = cmd                               { Ast.Herd.Cmd c }
  | C_MODEL;   s = STRING                 { Ast.Herd.C_model s }
  | ASM_MODEL; e = IDENTIFIER; s = STRING { Ast.Herd.Asm_model (e, s) }

id_or_default:
  | id = IDENTIFIER { id }
  | DEFAULT         { Machine.Id.default }

machine_stanza:
  | s = id_stanza(MACHINE, id_or_default, machine_item) { s }

machine_item:
  | b = enabled         { Ast.Machine.Enabled b }
  | VIA; v = via_stanza { Ast.Machine.Via     v }
  | l = litmus_stanza   { Ast.Machine.Litmus  l }

via_stanza:
  | LOCAL                                { Ast.Via.Local }
  | items = simple_stanza(SSH, ssh_item) { Ast.Via.Ssh items }

ssh_item:
  | USER;     user    = STRING { Ast.Ssh.User    user }
  | HOST;     host    = STRING { Ast.Ssh.Host    host }
  | COPY; TO; copy_to = STRING { Ast.Ssh.Copy_to copy_to }

compiler_stanza:
  | s = id_stanza(COMPILER, IDENTIFIER, compiler_item) { s }
  (* Compilers don't have a 'default' identifier. *)

compiler_item:
  | b = enabled                    { Ast.Compiler.Enabled b }
  | c = cmd                        { Ast.Compiler.Cmd     c }
  | vs = argv                      { Ast.Compiler.Argv    vs }
  | STYLE;   style = IDENTIFIER    { Ast.Compiler.Style   style }
  | EMITS;   emits = IDENTIFIER    { Ast.Compiler.Emits   emits }
  | HERD;    on    = BOOL          { Ast.Compiler.Herd    on }
  | MACHINE; mach  = id_or_default { Ast.Compiler.Machine mach }

cmd:
  | CMD; c = STRING { c }

argv:
  | ARGV; vs = STRING+ { vs }

enabled:
  | ENABLED; b = BOOL { b }

