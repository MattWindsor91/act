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

(** A miniature model of a memalloy-witness-style C program.

    Unlike {{!Ast}Ast}, which tries to be a fairly faithful C abstract
    syntax tree, this module describes a tiny subset of C that
    maps well to litmus tests, and does so in a fairly high-level
    manner.

    One can get a 'mini' C program by {{!Convert}converting} an AST
    to it (which may fail).  To get an AST (for printing, etc.), use
    {{!Reify}Reify}.
 *)

open Core_kernel
open Utils

include module type of Ast_basic
include module type of Mini_intf

type 'a named = (Identifier.t * 'a) [@@deriving eq, sexp]
(** Shorthand for pairs of items and their names. *)

type 'a id_assoc = (Identifier.t, 'a) List.Assoc.t [@@deriving sexp]
(** Shorthand for associative lists with identifier keys. *)

(** Abstract data type of (mini C) types. *)
module Type : sig
  (** Primitive types. *)
  module Basic : sig
    type t
    (** Opaque type of basic types. *)

    val int : t
    (** [int] is the int type. *)

    val atomic_int : t
    (** [atomic_int] is the atomic_int type. *)

    include Enum.Extension_table with type t := t
  end

  type t [@@deriving eq, sexp, compare]

  include Quickcheckable.S with type t := t

  val normal : Basic.t -> t
  (** [normal ty] lifts a basic type [ty] to a scalar type. *)

  val pointer_to : Basic.t -> t
  (** [pointer_to ty] lifts a basic type [ty] to a pointer type. *)

  val of_basic : Basic.t -> is_pointer:bool -> t
  (** [of_basic ty ~is_pointer] lifts a basic type [ty] to a pointer
      type if [is_pointer] is true, and a normal one otherwise. *)

  val deref : t -> t Or_error.t
  (** [deref ty] tries to strip a layer of pointer indirection off [ty].
      It fails if [ty] isn't a pointer type. *)

  val underlying_basic_type : t -> Basic.t
  (** [underlying_basic_type ty] gets [ty]'s basic type. *)

  val is_atomic : t -> bool
  (** [is_atomic ty] returns whether [ty] is an atomic type. *)
end

module Initialiser : sig
  type t

  val make : ty:Type.t -> ?value:Constant.t -> unit -> t
  (** [make ~ty ?value ()] makes an initialiser with type [ty] and
      optional initialised value [value]. *)

  include Quickcheck.S with type t := t
end

(** Somewhere assignable (a variable, or dereference thereof). *)
module Lvalue : sig
  type t [@@deriving sexp]

  val variable : Identifier.t -> t
  (** [variable id] constructs an lvalue pointing to variable [id].
      It doesn't do any validation. *)

  val deref : t -> t
  (** [deref lvalue] constructs a dereference ([*]) of another lvalue
      [lvalue].It doesn't do any validation. *)

  val is_deref : t -> bool
  (** [is_deref lvalue] returns [true] if [lvalue] is a dereference of
      another [lvalue], and [false] otherwise. *)

  module On_identifiers
    : Travesty.Traversable.S0_container
      with type t := t and type Elt.t = Identifier.t
  (** Traversing over identifiers in lvalues. *)

  include Quickcheckable.S with type t := t

  val underlying_variable : t -> Identifier.t
  (** [underlying_variable t] gets the underlying variable name of
     [t]. *)
end

(** An address (a lvalue, or reference thereto). *)
module Address : sig
  type t [@@deriving sexp]

  module On_lvalues
    : Travesty.Traversable.S0_container
      with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in addresses. *)

  val lvalue : Lvalue.t -> t
  (** [lvalue lv] lifts an lvalue [lv] to an address. *)

  val ref : t -> t
  (** [ref t] constructs a &-reference to [t]. *)

  val underlying_variable : t -> Identifier.t
  (** [underlying_variable t] gets the underlying variable name of
     [t]. *)
end


(** An atomic load operation. *)
module Atomic_load : sig
  type t [@@deriving sexp]

  (** {3 Traversals} *)

  module On_addresses : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Address.t
  (** Traversing over atomic-action addresses in atomic loads. *)

  module On_lvalues : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in atomic loads. *)

  (** {3 Constructors} *)

  val make : src:Address.t -> mo:Mem_order.t -> t
  (** [atomic_load ~src ~dst ~mo] constructs an explicit atomic load
      expression with source [src] and memory order [mo]. *)
end

(** An expression. *)
module Expression : sig
  type t [@@deriving sexp]

  (** {3 Traversals} *)

  module On_addresses
    : Travesty.Traversable.S0_container
        with type t := t and type Elt.t = Address.t
  (** Traversing over atomic-action addresses in expressions. *)

  module On_identifiers
    : Travesty.Traversable.S0_container
        with type t := t and type Elt.t = Identifier.t
  (** Traversing over identifiers in expressions. *)

  module On_lvalues
    : Travesty.Traversable.S0_container
        with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in expressions. *)

  (** {3 Constructors} *)

  val atomic_load : Atomic_load.t -> t
  (** [atomic_load a] lifts an atomic load [a] to an expression. *)

  val constant : Constant.t -> t
  (** [constant k] lifts a C constant [k] to an expression. *)

  val eq : t -> t -> t
  (** [eq l r] generates an equality expression. *)

  val lvalue : Lvalue.t -> t
  (** [lvalue lv] lifts a lvalue [lv] to an expression. *)
end

(** A non-atomic assignment. *)
module Assign : sig
  type t [@@deriving sexp]

  (** {3 Traversals} *)

  module On_addresses : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Address.t
  (** Traversing over atomic-action addresses in assignments. *)

  module On_lvalues : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in assignments. *)

  (** {3 Constructors} *)

  val make : lvalue:Lvalue.t -> rvalue:Expression.t -> t
  (** [make ~lvalue ~rvalue] constructs an assignment of [rvalue] to
     [lvalue]. *)
end

(** An atomic store operation. *)
module Atomic_store : sig
  type t [@@deriving sexp]

  (** {3 Traversals} *)

  module On_addresses : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Address.t
  (** Traversing over atomic-action addresses in atomic stores. *)

  module On_lvalues : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in atomic stores. *)

  (** {3 Constructors} *)

  val make : src:Expression.t -> dst:Address.t -> mo:Mem_order.t -> t
  (** [atomic_store ~src ~dst ~mo] constructs an explicit atomic store
     expression with source [src], destination [dst], and memory order
     [mo]. *)
end

(** An atomic compare-exchange operation. *)
module Atomic_cmpxchg : sig
  type t [@@deriving sexp]

  (** {3 Traversals} *)

  module On_addresses : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Address.t
  (** Traversing over atomic-action addresses in atomic
     compare-exchanges. *)

  module On_lvalues : Travesty.Traversable.S0_container
    with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in atomic compare-exchanges. *)

  (** {3 Constructors} *)

  val make
    :  obj:Address.t
    -> expected:Address.t
    -> desired:Expression.t
    -> succ:Mem_order.t
    -> fail:Mem_order.t
    -> t
  (** [make ~obj ~expected ~desired ~succ ~fail] constructs an
      explicit strong compare-exchange with object [obj], expected
      value store [expected], desired final value [desired], and
      memory orders [succ] on success and [fail] on failure. *)
end

(** A statement.

    We treat some things that are technically expressions in C as
    statements, for simplicity. *)
module Statement : sig
  type t [@@deriving sexp]

  module On_addresses
    : Travesty.Traversable.S0_container
        with type t := t and type Elt.t = Address.t
  (** Traversing over atomic-action addresses in statements. *)

  module On_identifiers
    : Travesty.Traversable.S0_container
        with type t := t and type Elt.t = Identifier.t
  (** Traversing over identifiers in statements. *)

  module On_lvalues
    : Travesty.Traversable.S0_container
        with type t := t and type Elt.t = Lvalue.t
  (** Traversing over lvalues in statements. *)

  (** {3 Constructors} *)

  val assign : Assign.t -> t
  (** [assign a] lifts an assignment [a] to a statement. *)

  val atomic_store : Atomic_store.t -> t
  (** [atomic_store a] lifts an atomic store [a] to a statement. *)

  val atomic_cmpxchg : Atomic_cmpxchg.t -> t
  (** [atomic_cmpxchg a] lifts an atomic compare-exchange [a] to a statement. *)

  val if_stm
    :  cond:Expression.t
    -> t_branch:t list
    -> ?f_branch:t list
    -> unit
    -> t
  (** [if_stm ~cond ~t_branch ?f_branch ()] creates an if statement
     with condition [cond], true branch [t_branch], and optional false
     branch [f_branch]. *)

  val nop : t
  (** [nop] is a no-operation statement; it corresponds to C's empty
     expression statement. *)

  (** {3 Paths} *)

  module rec Path :
    (S_statement_path
     with type stm = t and type 'a list_path := 'a List_path.t)
  and List_path :
    (S_statement_list_path
     with type stm = t and type 'a stm_path := 'a Path.t)
end

(** A function (less its name). *)
module Function : sig
  type t [@@deriving sexp]

  val make
    :  parameters:Type.t id_assoc
    -> body_decls:Initialiser.t id_assoc
    -> ?body_stms:Statement.t list
    -> unit
    -> t
  (** [make ~parameters ~body_decls ?body_stms] creates a function
     with the given contents. *)

  val parameters : t -> Type.t id_assoc
  (** [parameters func] gets [func]'s parameter list. *)

  val body_decls : t -> Initialiser.t id_assoc
    (** [body_decls func] gets [func]'s in-body variable
       declarations. *)

  val body_stms : t -> Statement.t list
    (** [body_decls func] gets [func]'s statements. *)

  val map
    :  t
    -> parameters:(Type.t id_assoc -> Type.t id_assoc)
    -> body_decls:(Initialiser.t id_assoc -> Initialiser.t id_assoc)
    -> body_stms:(Statement.t list -> Statement.t list)
    -> t
    (** [map func ~parameters ~body_decls ~body_stms] runs the given
        functions over the respective parts of a function. *)

  val cvars : t -> C_identifier.Set.t
  (** [cvars func] extracts a set of C variable names from
      [func]. *)

  module On_decls : Travesty.Traversable.S0_container
    with type t := t and type Elt.t := Initialiser.t named
    (** [On_decls] allows traversal over all of the declarations
        inside a function. *)
end

module Program : sig
  type t [@@deriving sexp]

  val make
   :  globals:(Initialiser.t id_assoc)
   -> functions:(Function.t id_assoc)
   -> t
   (** [make ~globals ~functions] makes a program with global variable
       declarations [globals] and function definitions [functions]. *)

 val cvars : t -> C_identifier.Set.t
 (** [cvars program] extracts a set of C variable names from
    [program]. *)

  module On_decls : Travesty.Traversable.S0_container
    with type t := t and type Elt.t := Initialiser.t named
    (** [On_decls] allows traversal over all of the declarations
        inside a program. *)
end

(** Functions for reifying a mini-model into an AST. *)
module Reify : sig
  val func : Identifier.t -> Function.t -> Ast.External_decl.t

  val program : Program.t -> Ast.Translation_unit.t
end

(** The mini-model, packaged up as a Litmus language.

    This language uses {{!Reify}Reify} for all of its pretty-printing
    needs. *)
module Litmus_lang : Litmus.Ast.Basic
  with type Statement.t =
         [ `Stm of Statement.t
         | `Decl of (Identifier.t * Initialiser.t)
         ]
   and type Program.t = (Identifier.t * Function.t)
   and type Constant.t = Constant.t
;;

(** The mini-model's full Litmus AST module. *)
module Litmus_ast : Litmus.Ast.S with module Lang = Litmus_lang

(** Pretty-printing for the mini-model's litmus AST. *)
module Litmus_pp : Litmus.Pp.S with module Ast = Litmus_ast

val litmus_cvars : Litmus_ast.Validated.t -> C_identifier.Set.t
(** litmus_cvars ast] gets the list of C variables referenced in a
   mini-C Litmus test. *)
