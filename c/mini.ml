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

open Core_kernel

let map_combine
    (xs : 'a list) ~(f : 'a -> 'b Or_error.t) : 'b list Or_error.t =
  xs
  |> List.map ~f
  |> Or_error.combine_errors
;;

type 'a named = (Ast_basic.Identifier.t * 'a)
[@@deriving sexp]

type 'a id_assoc = (Ast_basic.Identifier.t, 'a) List.Assoc.t
[@@deriving sexp]

module Type = struct
  type basic =
    | Int
    | Atomic_int
  [@@deriving sexp]
  ;;

  type t =
    | Normal of basic
    | Pointer_to of basic
  [@@deriving sexp]
  ;;
end

module Initialiser = struct
  type t =
    { ty    : Type.t
    ; value : Ast_basic.Constant.t option
    }
  [@@deriving sexp]
  ;;
end

module Lvalue = struct
  type t =
    | Variable of Ast_basic.Identifier.t
    | Deref    of t
  [@@deriving sexp, variants]
end

module Expression = struct
  type t =
    | Constant of Ast_basic.Constant.t
    | Lvalue   of Lvalue.t
  [@@deriving sexp, variants]
  ;;
end

module Statement = struct
  type t =
    | Assign of { lvalue : Lvalue.t
                ; rvalue : Expression.t
                }
    | Nop
  [@@deriving sexp, variants]
  ;;
end

module Function = struct
  type t =
    { parameters : Type.t id_assoc
    ; body_decls : Initialiser.t id_assoc
    ; body_stms  : Statement.t list
    }
  [@@deriving sexp, fields]
  ;;
end

module Program = struct
  type t =
    { globals   : Initialiser.t id_assoc
    ; functions : Function.t id_assoc
    }
  [@@deriving sexp, fields]
  ;;
end

module Reify = struct
  let to_initialiser (value : Ast_basic.Constant.t) : Ast.Initialiser.t =
    Assign (Constant value)
  ;;

  let basic_type_to_spec : Type.basic -> [> Ast.Type_spec.t] = function
    | Int -> `Int
    | Atomic_int -> `Defined_type "atomic_int"
  ;;

  let type_to_spec : Type.t -> [> Ast.Type_spec.t] = function
    | Normal     x
    | Pointer_to x -> basic_type_to_spec x
  ;;

  let type_to_pointer : Type.t -> Ast_basic.Pointer.t option = function
    | Normal     _ -> None
    | Pointer_to _ -> Some [[]]
  ;;

  let id_declarator
      (ty : Type.t) (id : Ast_basic.Identifier.t)
    : Ast.Declarator.t =
    { pointer = type_to_pointer ty; direct = Id id }
  ;;

  let decl (id : Ast_basic.Identifier.t) (elt : Initialiser.t) : Ast.Decl.t =
    { qualifiers = [ type_to_spec elt.ty ]
    ; declarator = [ { declarator  = id_declarator elt.ty id
                     ; initialiser = Option.map ~f:to_initialiser elt.value
                     }
                   ]
    }

  let decls : Initialiser.t id_assoc -> [> `Decl of Ast.Decl.t ] list =
    List.map ~f:(fun (k, v) -> `Decl (decl k v))
  ;;

  let func_parameter
      (id : Ast_basic.Identifier.t)
      (ty : Type.t)
    : Ast.Param_decl.t =
    { qualifiers = [ type_to_spec ty ]
    ; declarator = `Concrete (id_declarator ty id)
    }

  let func_parameters
      (parameters : Type.t id_assoc) : Ast.Param_type_list.t =
    { params = List.map ~f:(Tuple2.uncurry func_parameter) parameters
    ; style  = `Normal
    }
  ;;

  let func_signature
      (id : Ast_basic.Identifier.t)
      (parameters : Type.t id_assoc)
    : Ast.Declarator.t =
    { pointer = None
    ; direct = Fun_decl (Id id, func_parameters parameters)
    }
  ;;

  let rec lvalue_to_expr : Lvalue.t -> Ast.Expr.t = function
    | Variable v -> Identifier v
    | Deref    l -> Prefix (`Deref, lvalue_to_expr l)
  ;;

  let expr : Expression.t -> Ast.Expr.t = function
    | Constant k -> Constant k
    | Lvalue l -> lvalue_to_expr l
  ;;

  let stm : Statement.t -> Ast.Stm.t = function
    | Assign { lvalue; rvalue } ->
      Expr (Some (Binary (lvalue_to_expr lvalue, `Assign, expr rvalue)))
    | Nop -> Expr None
  ;;

  let func_body
      (ds : Initialiser.t id_assoc)
      (ss : Statement.t   list)
    : Ast.Compound_stm.t =
    decls ds @ List.map ~f:(fun x -> `Stm (stm x)) ss

  let func (id : Ast_basic.Identifier.t) (def : Function.t)
    : Ast.External_decl.t =
    `Fun
      { decl_specs = [ `Void ]
      ; signature  = func_signature id def.parameters
      ; decls      = []
      ; body       = func_body def.body_decls def.body_stms
      }
  ;;

  let program (prog : Program.t) : Ast.Translation_unit.t =
    List.concat
      [ decls                             prog.globals
      ; List.map ~f:(Tuple2.uncurry func) prog.functions
      ]
  ;;
end

module Litmus_lang : Litmus.Ast.Basic
  with type Statement.t = [`Stm of Statement.t | `Decl of Initialiser.t named]
   and type Program.t = Function.t named
   and type Constant.t = Ast_basic.Constant.t = (struct
    module Constant = Ast_basic.Constant

    module Statement = struct
      type t = [`Stm of Statement.t | `Decl of Initialiser.t named]
      [@@deriving sexp]
      let pp =
        Fmt.using
          (function
            | `Decl (id, init) -> `Decl (Reify.decl id init)
            | `Stm stm         -> `Stm  (Reify.stm stm))
          Ast.Litmus_lang.Statement.pp

      let empty () = `Stm (Statement.nop)
      let make_uniform = Travesty.T_list.right_pad ~padding:(empty ())
    end

    module Program = struct
      type t = Function.t named [@@deriving sexp]
      let name (n, _) = Some n
      let listing (_, fn) =
        List.map (Function.body_decls fn) ~f:(fun x -> `Decl x)
        @ List.map (Function.body_stms fn) ~f:(fun x -> `Stm x)
      let pp = Fmt.(using (Tuple2.uncurry Reify.func) Ast.External_decl.pp)
    end

    let name = "C"
  end)


module Litmus_ast = struct
  module A = Litmus.Ast.Make (Litmus_lang)
  include A
  include Litmus.Pp.Make_sequential (A)
end

module Convert = struct
  (** [sift_decls maybe_decl_list] tries to separate [maybe_decl_list]
     into a list of declarations followed immediately by a list of
     code, C89-style. *)
  let sift_decls :
    ([> `Decl of Ast.Decl.t ] as 'a) list -> (Ast.Decl.t list * ('a list)) Or_error.t =
    Travesty.T_list.With_errors.fold_m
      ~init:([], [])
      ~f:(fun (decls, rest) item ->
          match decls, rest, item with
          | _, [], `Decl d -> Or_error.return (d::decls, rest)
          | _, _ , `Decl _ -> Or_error.error_string
                                "Declarations must go before code."
          | _, _ , _       -> Or_error.return (decls, item::rest)
        )
  ;;

  (** [ensure_functions xs] makes sure that each member of [xs] is a
     function definition. *)
  let ensure_functions
    : Ast.External_decl.t list
      -> Ast.Function_def.t list Or_error.t =
    map_combine
      ~f:(
        function
        | `Fun f -> Or_error.return f
        | d      -> Or_error.error_s
                      [%message "Expected a function"
                        ~got:(d : Ast.External_decl.t) ]
      )
  ;;

  (** [ensure_statements xs] makes sure that each member of [xs] is a
     statement. *)
  let ensure_statements
    : Ast.Compound_stm.Elt.t list
      -> Ast.Stm.t list Or_error.t =
    map_combine
      ~f:(
        function
        | `Stm f -> Or_error.return f
        | d      -> Or_error.error_s
                      [%message "Expected a statement"
                        ~got:(d : Ast.Compound_stm.Elt.t) ]
      )
  ;;

  let defined_types : (string, Type.basic) List.Assoc.t =
    [ "atomic_int", Atomic_int ]

  let qualifiers_to_basic_type (quals : [> Ast.Decl_spec.t ] list)
    : Type.basic Or_error.t =
    let open Or_error.Let_syntax in
    match%bind Travesty.T_list.one quals with
    | `Int -> return Type.Int
    | `Defined_type t ->
      t
      |> List.Assoc.find ~equal:String.equal defined_types
      |> Result.of_option
        ~error:(Error.create_s
                  [%message "Unknown defined type" ~got:t])
    | #Ast.Type_spec.t as spec ->
      Or_error.error_s
        [%message "This type isn't supported (yet)"
            ~got:(spec : Ast.Type_spec.t)]
    | #Ast_basic.Type_qual.t as qual ->
      Or_error.error_s
        [%message "This type qualifier isn't supported (yet)"
            ~got:(qual : Ast_basic.Type_qual.t)]
    | #Ast_basic.Storage_class_spec.t as spec ->
      Or_error.error_s
        [%message "This storage-class specifier isn't supported (yet)"
            ~got:(spec : Ast_basic.Storage_class_spec.t)]
  ;;

  let declarator_to_id : Ast.Declarator.t ->
    (Ast_basic.Identifier.t * bool) Or_error.t = function
    | { pointer = Some [[]];
        direct = Id id } ->
      Or_error.return (id, true)
    | { pointer = Some _; _ } as decl ->
      Or_error.error_s
        [%message "Complex pointers not supported yet"
            ~declarator:(decl : Ast.Declarator.t)
        ]
    | { pointer = None;
        direct  = Id id } ->
      Or_error.return (id, false)
    | x ->
      Or_error.error_s
        [%message "Unsupported direct declarator"
            ~got:(x.direct : Ast.Direct_declarator.t)
        ]
  ;;

  let value_of_initialiser
    : Ast.Initialiser.t -> Ast_basic.Constant.t Or_error.t = function
    | Assign (Constant v) -> Or_error.return v
    | Assign x ->
      Or_error.error_s
        [%message "Expression not supported (must be constant)"
          (x : Ast.Expr.t)]
    | List   _ ->
      Or_error.error_string "List initialisers not supported"
  ;;

  let make_type (basic_type : Type.basic) (is_pointer : bool) : Type.t =
    if is_pointer then Pointer_to basic_type else Normal basic_type
  ;;

  (** [decl d] translates a declaration into an identifier-initialiser
     pair. *)
  let decl (d : Ast.Decl.t)
    : (Ast_basic.Identifier.t * Initialiser.t) Or_error.t =
    let open Or_error.Let_syntax in
    let%bind basic_type         = qualifiers_to_basic_type d.qualifiers in
    let%bind idecl              = Travesty.T_list.one d.declarator in
    let%bind (name, is_pointer) = declarator_to_id idecl.declarator in
    let%map  value = Travesty.T_option.With_errors.map_m idecl.initialiser
        ~f:value_of_initialiser
    in
    let ty = make_type basic_type is_pointer in
    (name, { Initialiser.ty; value })
  ;;

  let validate_func_void_type (f : Ast.Function_def.t)
    : Validate.t =
    match f.decl_specs with
    | [ `Void ] -> Validate.pass
    | xs -> Validate.fail_s
              [%message "Expected 'void'"
                ~got:(xs : Ast.Decl_spec.t list)]
  ;;

  let validate_func_no_knr : Ast.Function_def.t Validate.check =
    Validate.booltest
      (fun f -> List.is_empty f.Ast.Function_def.decls)
      ~if_false:"K&R style function definitions not supported"
  ;;

  let validate_func : Ast.Function_def.t Validate.check =
    Validate.all
      [ validate_func_void_type
      ; validate_func_no_knr
      ]
  ;;

  let param_decl : Ast.Param_decl.t -> Type.t named Or_error.t =
    function
    | { declarator = `Abstract _; _ } ->
      Or_error.error_string
        "Abstract parameter declarators not supported"
    | { qualifiers; declarator = `Concrete declarator } ->
      let open Or_error.Let_syntax in
      let%map basic_type       = qualifiers_to_basic_type qualifiers
      and     (id, is_pointer) = declarator_to_id declarator
      in
      let ty = make_type basic_type is_pointer in (id, ty)
  ;;

  let param_type_list : Ast.Param_type_list.t ->
    Type.t id_assoc Or_error.t = function
    | { style = `Variadic; _ } ->
      Or_error.error_string "Variadic arguments not supported"
    | { style = `Normal; params } ->
      map_combine ~f:param_decl params
  ;;

  let func_signature : Ast.Declarator.t ->
    (Ast_basic.Identifier.t * Type.t id_assoc) Or_error.t = function
    | { pointer = Some _; _ } ->
      Or_error.error_string "Pointers not supported yet"
    | { pointer = None;
        direct  = Fun_decl (Id name, param_list) } ->
      Or_error.(
        param_list |> param_type_list >>| Tuple2.create name
      )
    | x ->
      Or_error.error_s
        [%message "Unsupported function declarator"
            ~got:(x.direct : Ast.Direct_declarator.t)
        ]
  ;;

  let rec expr_to_lvalue
    : Ast.Expr.t -> Lvalue.t Or_error.t = function
    | Identifier id   -> Or_error.return (Lvalue.variable id)
    | Brackets expr -> expr_to_lvalue expr
    | Prefix (`Deref, expr) ->
      Or_error.(expr |> expr_to_lvalue >>| Lvalue.deref)
    | Prefix _ | Postfix _ | Binary _ | Ternary _ | Cast _
    | Call _ | Subscript _ | Field _ | Sizeof_type _ | String _ | Constant _
      as e ->
      Or_error.error_s
        [%message "Expected an lvalue here" ~got:(e : Ast.Expr.t)]
  ;;

  let rec expr
    : Ast.Expr.t -> Expression.t Or_error.t = function
    | Constant k -> Or_error.return (Expression.constant k)
    | Brackets e -> expr e
    | Prefix (`Deref, expr) ->
      Or_error.(expr |> expr_to_lvalue >>| Lvalue.deref >>| Expression.lvalue)
    | Prefix _ | Postfix _ | Binary _ | Ternary _ | Cast _
    | Call _ | Subscript _ | Field _ | Sizeof_type _ | String _ | Identifier _
      as e ->
      Or_error.error_s
        [%message "Unsupported expression" ~got:(e : Ast.Expr.t)]
  ;;

  let expr_stm : Ast.Expr.t -> Statement.t Or_error.t = function
    | Binary (l, `Assign, r) ->
      let open Or_error.Let_syntax in
      let%map lvalue = expr_to_lvalue l
      and     rvalue = expr r
      in Statement.assign ~lvalue ~rvalue
    | Brackets _ | Constant _
    | Prefix _ | Postfix _ | Binary _ | Ternary _ | Cast _
    | Call _ | Subscript _ | Field _ | Sizeof_type _ | String _ | Identifier _
      as e ->
      Or_error.error_s
        [%message "Unsupported expression statement" ~got:(e : Ast.Expr.t)]
  ;;

  let stm : Ast.Stm.t -> Statement.t Or_error.t = function
    | Expr None -> Or_error.return Statement.nop
    | Expr (Some e) -> expr_stm e
    | Continue | Break | Return _ | Label _ | Compound _
    | If _ | Switch _ | While _ | Do_while _ | For _ | Goto _
        as s ->
      Or_error.error_s
        [%message "Unsupported statement" ~got:(s : Ast.Stm.t)]
  ;;

  let func_body (body : Ast.Compound_stm.t)
    : (Initialiser.t id_assoc * Statement.t list) Or_error.t =
    let open Or_error.Let_syntax in
    let%bind (ast_decls, ast_nondecls) = sift_decls body in
    let%bind ast_stms = ensure_statements ast_nondecls in
    let%map  decls = map_combine ~f:decl ast_decls
    and      stms  = map_combine ~f:stm  ast_stms
    in (decls, stms)
  ;;

  let func (f : Ast.Function_def.t)
    : (Ast_basic.Identifier.t * Function.t) Or_error.t =
    let open Or_error.Let_syntax in
    let%bind () = Validate.result (validate_func f) in
    let%map  (name, parameters)      = func_signature f.signature
    and      (body_decls, body_stms) = func_body f.body
    in (name, { Function.parameters; body_decls; body_stms })
  ;;

  let translation_unit (prog : Ast.Translation_unit.t) : Program.t Or_error.t =
    let open Or_error.Let_syntax in
    let%bind (ast_decls, ast_nondecls) = sift_decls prog in
    let%bind ast_funs = ensure_functions ast_nondecls in
    let%map  decls = map_combine ~f:decl ast_decls
    and      funs  = map_combine ~f:func ast_funs
    in { Program.globals = decls; functions = funs }
  ;;

  module Litmus_conv = Litmus.Ast.Convert (struct
      module From = struct
        include Ast.Litmus
        module Lang = Ast.Litmus_lang
      end
      module To = Litmus_ast

      let program = func
      let constant = Or_error.return
    end)
  ;;

  let litmus
    : Ast.Litmus.Validated.t
      -> Litmus_ast.Validated.t Or_error.t =
    Litmus_conv.convert
  ;;
end
