open Core
open Lib

module AttFrontend =
  LangFrontend.Make (
      struct
        type token = ATTParser.token
        type ast = Ast.t

        let lex =
          let module T = ATTLexer.Make(LexUtils.Default) in
          T.token

        let parse lex lexbuf =
          Or_error.try_with
            ( fun () ->
                { Ast.syntax = Dialect.Att
                ; program = ATTParser.main lex lexbuf
                }
            )
      end)

module type Intf = sig
  include Dialect.Intf
  include PP.Printer
  include
    Language.Intf
    with type Constant.t = Ast.operand
     and type Location.t = Ast.location
     and type Instruction.t = Ast.instruction
     and type Statement.t = Ast.statement

  val make_jump_operand : string -> Ast.operand
end

module Make (T : Dialect.Intf) (P : PP.Printer) =
struct
  include T
  include P

  let make_jump_operand jsym =
    Ast.(
      let disp = DispSymbolic jsym in
      match T.symbolic_jump_type with
      | `Indirect ->
        OperandLocation (LocIndirect (Indirect.make ~disp ()))
      | `Immediate ->
        OperandImmediate disp
    )

  include
    Language.Make
      (struct
        let name = "X86"

        let is_program_label = Base.is_program_label

        let pp_comment = P.pp_comment

        module Location = struct
          type t = Ast.location
          let sexp_of_t = [%sexp_of: Ast.location]
          let t_of_sexp = [%of_sexp: Ast.location]

          let pp = P.pp_location

          let make_heap_loc l =
            Ast.(LocIndirect (Indirect.make ~disp:(DispSymbolic l) ()))
          ;;

          let indirect_abs_type (i : Ast.Indirect.t) =
            let open Language.AbsLocation in
            let open Ast.Indirect in
            match (seg i), (disp i), (base i), (index i) with
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
            | Ast.LocReg ESP
            | LocReg EBP -> StackPointer
            | Ast.LocReg _ -> GeneralRegister
            | Ast.LocIndirect i -> indirect_abs_type i
        end

        module Instruction = struct
          open Ast

          type t = Ast.instruction
          let sexp_of_t = [%sexp_of: Ast.instruction]
          let t_of_sexp = [%of_sexp: Ast.instruction]

          type loc = Location.t

          let pp = P.pp_instruction

          let jump l =
            { prefix = None
            ; opcode = OpJump None
            ; operands = [ make_jump_operand l ]
            }

          let basic_instruction_type
            : [< Ast.basic_opcode] -> Language.AbsInstruction.t =
            let open Language.AbsInstruction in
            function
            | `Add    -> Arith
            | `Call   -> Call
            | `Cmp    -> Compare
            | `Leave  -> Call
            | `Mfence -> Fence
            | `Mov    -> Move
            | `Nop    -> Nop
            | `Pop    -> Stack
            | `Push   -> Stack
            | `Ret    -> Return
            | `Sub    -> Arith
            | `Xor    -> Logical

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

          let basic_operands (o : [< Ast.basic_opcode])
              (operands : Ast.operand list) =
            let open Language.AbsOperands in
            match o with
            | `Leave
            | `Mfence
            | `Nop
            | `Ret -> zero_operands operands
            | `Add
            | `Sub
            | `Mov
            | `Xor -> src_dst_operands operands
            (* TODO(@MattWindsor91): analyse other opcodes! *)
            | `Call
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
                      (Ast.LocIndirect i) ->
                    begin
                      match Ast.Indirect.disp i with
                      | Some (Ast.DispSymbolic s) -> SymbolicJump s
                      | _ -> Other
                    end
                  | Ast.OperandImmediate (Ast.DispSymbolic s) -> SymbolicJump s
                  | _ -> Other
                end
              | _ -> Erroneous
            )

          let abs_operands {opcode; operands; _} =
            match opcode with
            | Ast.OpBasic b -> basic_operands b operands
            | Ast.OpSized (b, _) -> basic_operands b operands
            | Ast.OpJump _ -> jump_operands operands
            | _ -> Language.AbsOperands.Other

          let%expect_test "abs_operands: nop -> none" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = Ast.OpBasic `Nop
                 ; operands = []
                 ; prefix = None
                 });
            [%expect {| none |}]

          let%expect_test "abs_operands: jmp, AT&T style" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = Ast.OpJump None
                 ; operands =
                     [ Ast.OperandLocation
                         (Ast.LocIndirect
                            (Ast.Indirect.make
                               ~disp:(Ast.DispSymbolic "L1") ()))
                     ]
                 ; prefix = None
                 });
            [%expect {| jump->L1 |}]

          let%expect_test "abs_operands: nop $42 -> error" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = Ast.OpBasic `Nop
                 ; operands = [ Ast.OperandImmediate
                                  (Ast.DispNumeric 42) ]
                 ; prefix = None
                 });
            [%expect {| <invalid operands> |}]

          let%expect_test "abs_operands: mov %ESP, %EBP" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = Ast.OpBasic `Mov
                 ; operands = [ Ast.OperandLocation (Ast.LocReg ESP)
                              ; Ast.OperandLocation (Ast.LocReg EBP)
                              ]
                 ; prefix = None
                 });
            [%expect {| &stack -> &stack |}]

          let%expect_test "abs_operands: movl %ESP, %EBP" =
            Format.printf "%a@."
              Language.AbsOperands.pp
              (abs_operands
                 { opcode = Ast.OpSized (`Mov, SLong)
                 ; operands = [ Ast.OperandLocation (Ast.LocReg ESP)
                              ; Ast.OperandLocation (Ast.LocReg EBP)
                              ]
                 ; prefix = None
                 });
            [%expect {| &stack -> &stack |}]

          let abs_type ({opcode; _} : Ast.instruction) =
            let open Language.AbsInstruction in
            match opcode with
            | Ast.OpDirective _ ->
              (* handled by abs_type below. *)
              Other
            | Ast.OpJump _ -> Jump
            | Ast.OpBasic b -> basic_instruction_type b
            | Ast.OpSized (b, _) -> basic_instruction_type b
            | Ast.OpUnknown _ -> Unknown

          module OnSymbolsS = struct
            type t = string
            type cont = Ast.instruction
            let fold_map = Ast.fold_map_instruction_symbols
          end

          module OnLocationsS = struct
            type t = Location.t
            type cont = Ast.instruction
            let fold_map = Ast.fold_map_instruction_locations
          end
        end

        module Statement = struct
          open Ast

          type t = Ast.statement
          let sexp_of_t = [%sexp_of: Ast.statement]
          let t_of_sexp = [%of_sexp: Ast.statement]
          let pp = P.pp_statement

          type ins = Ast.instruction

          let empty () = Ast.StmNop
          let label s = Ast.StmLabel s
          let instruction i = Ast.StmInstruction i

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
            type cont = Ast.statement
            let fold_map = Ast.fold_map_statement_symbols
          end

          module OnInstructionsS = struct
            type t = Instruction.t
            type cont = Ast.statement
            let fold_map = Ast.fold_map_statement_instructions
          end
        end

        module Constant = struct
          (* TODO: this is too weak *)
          type t = Ast.operand
          let sexp_of_t = [%sexp_of: Ast.operand]
          let t_of_sexp = [%of_sexp: Ast.operand]
          let pp = P.pp_operand

          let zero = Ast.OperandImmediate (Ast.DispNumeric 0)
        end
      end)
end

module ATT = Make (Dialect.ATT) (PP.ATT)

let%expect_test "abs_operands: add $-16, %ESP, AT&T" =
  Format.printf "%a@."
    Language.AbsOperands.pp
    (ATT.Instruction.abs_operands
       { opcode = Ast.OpBasic `Add
       ; operands = [ Ast.OperandImmediate (Ast.DispNumeric (-16))
                    ; Ast.OperandLocation (Ast.LocReg ESP)
                    ]
       ; prefix = None
       });
  [%expect {| $-16 -> &stack |}]

module Intel = Make (Dialect.Intel) (PP.Intel)

let%expect_test "abs_operands: add ESP, -16, Intel" =
  Format.printf "%a@."
    Language.AbsOperands.pp
    (Intel.Instruction.abs_operands
       { opcode = Ast.OpBasic `Add
       ; operands = [ Ast.OperandLocation (Ast.LocReg ESP)
                    ; Ast.OperandImmediate (Ast.DispNumeric (-16))
                    ]
       ; prefix = None
       });
  [%expect {| $-16 -> &stack |}]

module Herd7 = Make (Dialect.Herd7) (PP.Herd7)

let lang_of_dialect =
  function
  | Dialect.Att   -> (module ATT : Intf)
  | Dialect.Intel -> (module Intel : Intf)
  | Dialect.Herd7 -> (module Herd7 : Intf)

let frontend_of_dialect =
  function
  | Dialect.Att
    -> Or_error.return (module AttFrontend : LangFrontend.Intf with type ast = Ast.t)
  | d ->
    Or_error.error "x86 dialect unsupported" d [%sexp_of: Dialect.t]
