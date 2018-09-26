(* This file is part of 'act'.

Copyright (c) 2018 by Matt Windsor

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
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. *)

open Core
open Lang
open Utils.MyContainers

module type Intf = sig
  type statement

  val sanitise : statement list -> statement list list
end

module type LangHook = sig
  type statement

  val on_program : statement list -> statement list
  val on_statement : statement -> statement
end

module NullLangHook (LS : Language.Intf) =
  struct
    type statement = LS.Statement.t

    let on_program = Fn.id
    let on_statement = Fn.id
  end

let mangler =
  (* We could always just use something like Base36 here, but this
     seems a bit more human-readable. *)
  String.Escaping.escape_gen_exn
    ~escape_char:'Z'
    ~escapeworthy_map:[ '_', 'U'
                      ; '$', 'D'
                      ; '.', 'P'
                      ; 'Z', 'Z'
                      ]
let mangle ident =
  Staged.unstage mangler ident

let%expect_test "mangle: sample" =
  print_string (mangle "_foo$bar.BAZ");
  [%expect {| ZUfooZDbarZPBAZZ |}]

module T (LS : Language.Intf) (LH : LangHook with type statement = LS.Statement.t) =
  struct
    let remove_nops = MyList.exclude ~f:LS.Statement.is_nop
    let remove_directives = MyList.exclude ~f:LS.Statement.is_directive

    let split_programs stms =
      (* Adding a nop to the start forces there to be some
         instructions before the first program, meaning we can
         simplify discarding such instructions. *)
      let progs =
        (LS.Statement.nop() :: stms)
        |> List.group ~break:(Fn.const LS.Statement.is_program_boundary)
      in
      List.drop progs 1
    (* TODO(MattWindsor91): divine the end of the program. *)

    let make_programs_uniform nop ps =
      let maxlen =
        ps
        |> (List.max_elt ~compare:(fun x y -> Int.compare (List.length x) (List.length y)))
        |> Option.value_map ~f:(List.length) ~default:0
      in
      List.map ~f:(fun p -> p @ List.init (maxlen - List.length p)
                                          ~f:(Fn.const nop))
               ps

    (** [mangle_identifiers] reduces identifiers into a form that herd
       can parse. *)
    let mangle_identifiers stm =
      LS.Statement.map_symbols ~f:mangle stm

    (** [sanitise_stm] performs sanitisation at the single statement
       level. *)
    let sanitise_stm stm =
      stm
      |> LH.on_statement
      |> mangle_identifiers

    let all_jump_symbols_in prog =
      prog
      |> List.filter ~f:LS.Statement.is_jump
      |> List.map ~f:LS.Statement.symbol_set
      |> Language.SymSet.union_list

    let irrelevant_instruction_types =
      Language.AISet.of_list
        [ Language.AICall
        ; Language.AIStack
        ]

    let remove_irrelevant_instructions =
      MyList.exclude ~f:(LS.Statement.instruction_mem irrelevant_instruction_types)

    (** [remove_dead_labels prog] removes all labels in [prog] whose symbols
        aren't mentioned in jump instructions. *)
    let remove_dead_labels prog =
      let jsyms = all_jump_symbols_in prog in
      List.filter
        ~f:(fun stm -> match LS.Statement.statement_type stm with
                       | Language.ASLabel l -> Language.SymSet.mem jsyms l
                       | _ -> true)
        prog

    (** [sanitise_program] performs sanitisation on a single program. *)
    let sanitise_program prog =
      prog
      |> LH.on_program
      |> remove_nops
      |> remove_directives
      |> remove_irrelevant_instructions
      |> remove_dead_labels
      |> List.map ~f:sanitise_stm

    let sanitise_programs progs =
      progs
      |> List.map ~f:sanitise_program
      |> make_programs_uniform (LS.Statement.nop ())

    let sanitise stms = sanitise_programs (split_programs stms)
  end

(* TODO(@MattWindsor91): should this move someplace else? *)

module X86ATT =
  struct
    type statement = X86Ast.statement

    open X86Ast

    let negate = function
      | DispNumeric k -> OperandImmediate (DispNumeric (-k))
      | DispSymbolic s -> OperandBop ( OperandImmediate (DispNumeric 0)
                                     , BopMinus
                                     , OperandImmediate (DispSymbolic s)
                                     )

    let sub_to_add =
      function
      | StmInstruction
        (* NB: When we adapt this for Intel, src and dest'll swap. *)
        ( { opcode = X86OpSub sz
          ; operands = [ OperandImmediate src; dst ]
          ; _
          } as op ) ->
         StmInstruction
           { op with opcode = X86OpAdd sz
                   ; operands = [ negate src; dst ]
           }
      | x -> x

    let on_statement stm =
      stm
      |> sub_to_add
    let on_program = Fn.id
  end
