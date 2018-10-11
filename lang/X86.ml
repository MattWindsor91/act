open Core

module AttFrontend =
  LangFrontend.Make (
      struct
        type token = X86ATTParser.token
        type ast = X86Ast.t

        let lex =
          let module T = X86ATTLexer.Make(LexUtils.Default) in
          T.token

        let parse lex lexbuf =
          Or_error.try_with
            ( fun () ->
                { X86Ast.syntax = X86Dialect.Att
                ; program = X86ATTParser.main lex lexbuf
                }
            )
      end)

module type Lang = sig
  include X86Dialect.Intf
  include X86PP.S
  include
    Language.Intf
    with type Constant.t = X86Ast.operand
     and type Location.t = X86Ast.location
     and type Instruction.t = X86Ast.instruction
     and type Statement.t = X86Ast.statement

  val make_jump_operand : string -> X86Ast.operand
end

module Make (T : X86Dialect.Intf) (P : X86PP.S) =
struct
  include T
  include P

  let make_jump_operand jsym =
    X86Ast.(
      let jdisp = DispSymbolic jsym in
      match T.symbolic_jump_type with
      | `Indirect ->
        OperandLocation (LocIndirect (in_disp_only jdisp))
      | `Immediate ->
        OperandImmediate jdisp
    )

  include
    Language.Make
      (struct
        let name = (Language.X86 (T.dialect))

        let is_program_label = X86Base.is_program_label

        module Location = struct
          type t = X86Ast.location
          let sexp_of_t = [%sexp_of: X86Ast.location]
          let t_of_sexp = [%of_sexp: X86Ast.location]

          let pp = P.pp_location

          let make_heap_loc l =
            l
            |> X86Ast.DispSymbolic
            |> X86Ast.in_disp_only
            |> X86Ast.LocIndirect

          let indirect_abs_type ( { in_seg; in_disp; in_base; in_index } : X86Ast.indirect) =
            let open Language.AbsLocation in
            match in_seg, in_disp, in_base, in_index with
            (* Typically, [ EBP - i ] is a stack location: EBP is the
               frame pointer, and the x86 stack grows downwards. *)
            | None, Some (DispNumeric i), Some EBP, None ->
              StackOffset i
            (* This is the same as [ EBP - 0 ]. *)
            | None, None, Some ESP, None ->
              StackOffset 0
            (* This may be over-optimistic. *)
            | None, Some (DispSymbolic s), None, None ->
              Heap s
            | _, _, _, _ -> Unknown

          let abs_type =
            let open Language.AbsLocation in
            function
            | X86Ast.LocReg ESP
            | LocReg EBP -> StackPointer
            | X86Ast.LocReg _ -> GeneralRegister
            | X86Ast.LocIndirect i -> indirect_abs_type i
        end

        module Instruction = struct
          open X86Ast

          type t = X86Ast.instruction
          let sexp_of_t = [%sexp_of: X86Ast.instruction]
          let t_of_sexp = [%of_sexp: X86Ast.instruction]

          type loc = Location.t

          let pp = P.pp_instruction

          let jump l =
            { prefix = None
            ; opcode = OpJump None
            ; operands = [ make_jump_operand l ]
            }

          let basic_instruction_type
            : [< X86Ast.basic_opcode] -> Language.AbsInstruction.t =
            let open Language.AbsInstruction in
            function
            | `Add    -> Arith
            | `Cmp    -> Compare
            | `Leave  -> Call
            | `Mfence -> Fence
            | `Mov    -> Move
            | `Nop    -> Nop
            | `Pop    -> Stack
            | `Push   -> Stack
            | `Ret    -> Return
            | `Sub    -> Arith

          let zero_operands (operands : operand list)
            : Language.AbsOperands.t =
            let open Language.AbsOperands in
            if List.is_empty operands
            then None
            else Erroneous

          let src_dst_operands (operands : operand list)
            : Language.AbsOperands.t =
            let open Language.AbsOperands in
            let open T in
            to_src_dst operands
            |> Option.value_map
              ~f:(function
                  | { src = OperandLocation s
                    ; dst = OperandLocation d
                    } ->
                    LocTransfer
                      { src = Location.abs_type s
                      ; dst = Location.abs_type d
                      }
                  | { src = OperandImmediate (DispNumeric k)
                    ; dst = OperandLocation d
                    } ->
                    IntImmediate
                      { src = k
                      ; dst = Location.abs_type d
                      }
                  | _ -> None (* TODO(@MattWindsor91): flag erroneous *)
                )
              ~default:None

          let basic_operands (o : [< X86Ast.basic_opcode])
              (operands : X86Ast.operand list) =
            let open Language.AbsOperands in
            match o with
            | `Leave
            | `Mfence
            | `Nop
            | `Ret -> zero_operands operands
            | `Add
            | `Sub
            | `Mov -> src_dst_operands operands
            (* TODO(@MattWindsor91): analyse other opcodes! *)
            | `Cmp
            | `Pop
            | `Push -> Other

          let jump_operands =
            Language.AbsOperands.(
              function
              | [o] ->
                begin
                  match o with
                  | OperandLocation
                      (X86Ast.LocIndirect
                         { in_disp = Some (X86Ast.DispSymbolic s)
                         ; in_base = None
                         ; in_index = None
                         ; in_seg = None
                         }
                      )
                  | X86Ast.OperandImmediate
                      (X86Ast.DispSymbolic s)
                    -> SymbolicJump s
                  | _ -> Other
                end
              | _ -> Erroneous
            )

          let abs_operands {opcode; operands; _} =
            match opcode with
            | X86Ast.OpBasic b -> basic_operands b operands
            | X86Ast.OpSized (b, _) -> basic_operands b operands
            | X86Ast.OpJump _ -> jump_operands operands
            | _ -> Language.AbsOperands.Other

          let%expect_test "abs_operands: nop -> none" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = X86Ast.OpBasic `Nop
                 ; operands = []
                 ; prefix = None
                 });
            [%expect {| none |}]

          let%expect_test "abs_operands: jmp, AT&T style" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = X86Ast.OpJump None
                 ; operands =
                     [ X86Ast.OperandLocation
                         (X86Ast.LocIndirect
                            (X86Ast.in_disp_only
                               (X86Ast.DispSymbolic "L1")))
                     ]
                 ; prefix = None
                 });
            [%expect {| jump->L1 |}]

          let%expect_test "abs_operands: nop $42 -> error" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = X86Ast.OpBasic `Nop
                 ; operands = [ X86Ast.OperandImmediate
                                  (X86Ast.DispNumeric 42) ]
                 ; prefix = None
                 });
            [%expect {| <invalid operands> |}]

          let%expect_test "abs_operands: mov %ESP, %EBP" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = X86Ast.OpBasic `Mov
                 ; operands = [ X86Ast.OperandLocation (X86Ast.LocReg ESP)
                              ; X86Ast.OperandLocation (X86Ast.LocReg EBP)
                              ]
                 ; prefix = None
                 });
            [%expect {| &stack -> &stack |}]

          let%expect_test "abs_operands: movl %ESP, %EBP" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = X86Ast.OpSized (`Mov, X86SLong)
                 ; operands = [ X86Ast.OperandLocation (X86Ast.LocReg ESP)
                              ; X86Ast.OperandLocation (X86Ast.LocReg EBP)
                              ]
                 ; prefix = None
                 });
            [%expect {| &stack -> &stack |}]

          let abs_type ({opcode; _} : X86Ast.instruction) =
            let open Language.AbsInstruction in
            match opcode with
            | X86Ast.OpDirective _ ->
              (* handled by abs_type below. *)
              Other
            | X86Ast.OpJump _ -> Jump
            | X86Ast.OpBasic b -> basic_instruction_type b
            | X86Ast.OpSized (b, _) -> basic_instruction_type b
            | X86Ast.OpUnknown _ -> Unknown

          module OnSymbolsS = struct
            type t = string
            type cont = X86Ast.instruction
            let fold_map = X86Ast.fold_map_instruction_symbols
          end

          module OnLocationsS = struct
            type t = Location.t
            type cont = X86Ast.instruction
            let fold_map = X86Ast.fold_map_instruction_locations
          end
        end

        module Statement = struct
          open X86Ast

          type t = X86Ast.statement
          let sexp_of_t = [%sexp_of: X86Ast.statement]
          let t_of_sexp = [%of_sexp: X86Ast.statement]
          let pp = P.pp_statement

          type ins = X86Ast.instruction

          let empty () = X86Ast.StmNop
          let label s = X86Ast.StmLabel s
          let instruction i = X86Ast.StmInstruction i

          let abs_type =
            let open Language.AbsStatement in
            function
            | StmInstruction { opcode = OpDirective s; _ } ->
              Directive s
            | StmInstruction i -> Instruction (Instruction.abs_type i)
            | StmLabel l -> Label l
            | StmNop -> Blank

          module OnSymbolsS = struct
            type t = string
            type cont = X86Ast.statement
            let fold_map = X86Ast.fold_map_statement_symbols
          end

          module OnInstructionsS = struct
            type t = Instruction.t
            type cont = X86Ast.statement
            let fold_map = X86Ast.fold_map_statement_instructions
          end
        end

        module Constant = struct
          (* TODO: this is too weak *)
          type t = X86Ast.operand
          let sexp_of_t = [%sexp_of: X86Ast.operand]
          let t_of_sexp = [%of_sexp: X86Ast.operand]
          let pp = P.pp_operand

          let zero = X86Ast.OperandImmediate (X86Ast.DispNumeric 0)
        end
      end)
end

module ATT = Make (X86Dialect.ATT) (X86PP.ATT)

let%expect_test "abs_operands: add $-16, %ESP, AT&T" =
  Format.printf "%a@."
    Language.AbsOperands.pp
    (ATT.Instruction.abs_operands
       { opcode = X86Ast.OpBasic `Add
       ; operands = [ X86Ast.OperandImmediate (X86Ast.DispNumeric (-16))
                    ; X86Ast.OperandLocation (X86Ast.LocReg ESP)
                    ]
       ; prefix = None
       });
  [%expect {| $-16 -> &stack |}]

module Intel = Make (X86Dialect.Intel) (X86PP.Intel)

let%expect_test "abs_operands: add ESP, -16, Intel" =
  Format.printf "%a@."
    Language.AbsOperands.pp
    (Intel.Instruction.abs_operands
       { opcode = X86Ast.OpBasic `Add
       ; operands = [ X86Ast.OperandLocation (X86Ast.LocReg ESP)
                    ; X86Ast.OperandImmediate (X86Ast.DispNumeric (-16))
                    ]
       ; prefix = None
       });
  [%expect {| $-16 -> &stack |}]

module Herd7 = Make (X86Dialect.Herd7) (X86PP.Herd7)
