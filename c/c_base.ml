(****************************************************************************)
(*                           the diy toolsuite                              *)
(*                                                                          *)
(* Jade Alglave, University College London, UK.                             *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                          *)
(*                                                                          *)
(* Copyright 2015-present Institut National de Recherche en Informatique et *)
(* en Automatique and the authors. All rights reserved.                     *)
(*                                                                          *)
(* This software is governed by the CeCILL-B license under French law and   *)
(* abiding by the rules of distribution of free software. You can use,      *)
(* modify and/ or redistribute the software under the terms of the CeCILL-B *)
(* license as circulated by CEA, CNRS and INRIA at the following URL        *)
(* "http://www.cecill.info". We also give a copy in LICENSE.txt.            *)
(****************************************************************************)

open Core_kernel

let string_of_annot = Mem_order_or_annot.pp_annot

type reg = string

let parse_reg s = Some s
let pp_reg r = r
let reg_compare = String.compare

let symb_reg_name r =
  let len = String.length r in
  assert (len > 0) ;
  match r.[0] with
  | '%' -> Some (String.drop_prefix r 1)
  | _ -> None

let symb_reg r = sprintf "%%%s" r

type mem_order = Mem_order.t

type barrier = Mem_order_or_annot.t

let pp_barrier m =
  let open Mem_order_or_annot in
  match m with
  | MO mo -> "atomic_thread_fence("^(Mem_order.pp_mem_order mo)^")"
  | AN a -> "Fence{"^string_of_annot a^"}"

let barrier_compare = Pervasives.compare

type mutex_kind = MutexLinux | MutexC11

type return = OpReturn | FetchOp

type expression =
  | Const of Parsed_constant.v
  | LoadReg of reg
  | LoadMem of expression * Mem_order_or_annot.t
  | Op of Op.op * expression * expression
  | Exchange of expression * expression * Mem_order_or_annot.t
  | CmpExchange of expression * expression * expression  * Mem_order_or_annot.annot
  | Fetch of expression * Op.op * expression * mem_order
  | ECall of string * expression list
  | ECas of expression * expression * expression * mem_order * mem_order * bool
  | TryLock of expression * mutex_kind
  | IsLocked of expression * mutex_kind
  | AtomicOpReturn of expression * Op.op * expression * return * Mem_order_or_annot.annot
  | AtomicAddUnless of expression * expression * expression * bool (* ret bool *) | ExpSRCU of expression * Mem_order_or_annot.annot

type instruction =
  | Fence of barrier
  | Seq of instruction list * bool (* scope ? *)
  | If of expression * instruction * instruction option
  | DeclReg of C_type.t * reg
  | StoreReg of C_type.t option * reg * expression
  | StoreMem of expression * expression * Mem_order_or_annot.t
  | Lock of expression * mutex_kind
  | Unlock of expression * mutex_kind
  | AtomicOp of expression * Op.op * expression
  | InstrSRCU of expression * Mem_order_or_annot.annot
  | Symb of string
  | PCall of string * expression list

type parsedInstruction = instruction

let dump_op =
  let open Op in
  function
    | Add -> "add"
    | Sub -> "sub"
    | Or -> "or"
    | Xor -> "xor"
    | And -> "and"
    | _ -> assert false

let dump_ws = function
  | true  -> "strong"
  | false -> "weak"

let rec dump_expr =
  let open Mem_order_or_annot in
  function
    | Const c -> Parsed_constant.pp_v c
    | LoadReg(r) -> r
    | LoadMem(LoadReg r,AN []) ->
        sprintf "*%s" r
    | LoadMem(l,AN a) ->
        sprintf "__load{%s}(%s)" (string_of_annot a) (dump_expr l)
    | LoadMem(l,MO mo) ->
        sprintf "atomic_load_explicit(%s,%s)"
          (dump_expr l) (Mem_order.pp_mem_order mo)
    | Op(op,e1,e2) ->
        sprintf "%s %s %s" (dump_expr e1) (Op.pp_op op) (dump_expr e2)
    | Exchange(l,e,MO mo) ->
        sprintf "atomic_exchange_explicit(%s,%s,%s)"
          (dump_expr l) (dump_expr e) (Mem_order.pp_mem_order mo)
    | Exchange(l,e,AN a) ->
        sprintf "__xchg{%s}(%s,%s)"
          (string_of_annot a) (dump_expr l) (dump_expr e)
    | CmpExchange(e1,e2,e3,a) ->
        sprintf "__cmpxchg{%s}(%s,%s,%s)"
          (string_of_annot a) (dump_expr e1) (dump_expr e2) (dump_expr e3)
    | Fetch(l,op,e,mo) ->
        sprintf "atomic_fetch_%s_explicit(%s,%s,%s);"
          (dump_op op) (dump_expr l) (dump_expr e)
          (Mem_order.pp_mem_order mo)
    | ECall(f,es) ->
        sprintf "%s(%s)" f (dump_args es)
    | ECas(e1,e2,e3,Mem_order.SC,Mem_order.SC,strong) ->
        sprintf "atomic_compare_exchange_%s(%s,%s,%s)"
          (dump_ws strong)
          (dump_expr e1) (dump_expr e2) (dump_expr e3)

    | ECas(e1,e2,e3,mo1,mo2,strong) ->
        sprintf "atomic_compare_exchange_%s_explicit(%s,%s,%s,%s,%s)"
          (dump_ws strong)
          (dump_expr e1) (dump_expr e2) (dump_expr e3)
          (Mem_order.pp_mem_order mo1) (Mem_order.pp_mem_order mo2)
    | TryLock (_,MutexC11) -> assert false
    | TryLock (e,MutexLinux) ->
        sprintf "spin_trylock(%s)" (dump_expr e)
    | IsLocked (_,MutexC11) -> assert false
    | IsLocked (e,MutexLinux) ->
        sprintf "spin_islocked(%s)" (dump_expr e)
    | AtomicOpReturn (loc,op,e,ret,a) ->
        sprintf "__atomic_%s{%s}(%s,%s,%s)"
          (match ret with OpReturn -> "op_return" | FetchOp -> "fetch_op")
          (string_of_annot a)
          (dump_expr loc) (Op.pp_op op) (dump_expr e)
    | AtomicAddUnless (loc,a,u,retbool) ->
        sprintf "%satomic_op_return(%s,%s,%s)"
          (if retbool then "" else "__")
          (dump_expr loc) (dump_expr a) (dump_expr u)
    | ExpSRCU(loc,a) ->
        sprintf "__SRCU{%s}(%s)"
          (string_of_annot a)
          (dump_expr loc)

and dump_args es = String.concat ~sep:"," (List.map ~f:dump_expr es)

let rec do_dump_instruction indent =
  let pindent fmt = ksprintf (fun msg -> indent ^ msg) fmt in
  let open Mem_order_or_annot in
  function
  | Fence b -> indent ^ pp_barrier b^";"
  | Seq (l,false) ->
      String.concat ~sep:"\n"
        (List.map ~f:(do_dump_instruction indent) l)
  | Seq (l,true) ->
      let seq =
        String.concat ~sep:""
          (List.map ~f:(do_dump_instruction (indent^"  ")) l) in
      indent ^ "{\n" ^ seq ^ indent ^ "}\n"
  | If(c,t,e) ->
     let els =  match e with
       | None -> ""
       | Some e -> "else "^do_dump_instruction indent e in
     indent ^ "if("^dump_expr c^") "^
     do_dump_instruction indent t^els
  | StoreReg(None,r,e) ->
     pindent "%s = %s;" r (dump_expr e)
  | StoreReg(Some t,r,e) ->
     pindent "%s %s = %s;" (C_type.dump t) r (dump_expr e)
  | DeclReg(t,r) ->
     pindent "%s %s;" (C_type.dump t) r
  | StoreMem(LoadReg r,e,AN []) ->
     pindent "*%s = %s;" r (dump_expr e)
  | StoreMem(l,e,AN a) ->
      pindent "__store{%s}(%s,%s);"
        (string_of_annot a) (dump_expr l) (dump_expr e)
  | StoreMem(l,e,MO mo) ->
     pindent "atomic_store_explicit(%s,%s,%s);"
             (dump_expr l) (dump_expr e) (Mem_order.pp_mem_order mo)
  | Lock (l,MutexC11) ->
     pindent "lock(%s);" (dump_expr l)
  | Unlock (l,MutexC11) ->
     pindent "unlock(%s);" (dump_expr l)
  | Lock (l,MutexLinux) ->
     pindent "spin_lock(%s);" (dump_expr l)
  | Unlock (l,MutexLinux) ->
      pindent "spin_unlock(%s);" (dump_expr l)
  | AtomicOp(l,op,e) ->
      pindent "atomic_%s(%s,%s);" (dump_op op)
        (dump_expr l) (dump_expr e)
  | InstrSRCU(loc,a) ->
      pindent "__SRCU{%s}(%s)"
          (string_of_annot a)
          (dump_expr loc)
  | Symb s -> pindent "codevar:%s;" s
  | PCall (f,es) ->
      pindent "%s(%s);" f (dump_args es)

let dump_instruction = do_dump_instruction ""

let pp_instruction _mode = dump_instruction

let allowed_for_symb = List.map ~f:(fun x -> "r"^(string_of_int x))
                                (Misc.interval 0 64)

let fold_regs (_fc,_fs) acc _ins = acc
let map_regs _fc _fs ins = ins
let fold_addrs _f acc _ins = acc
let map_addrs _f ins = ins
let norm_ins ins = ins
let get_next _ins = Warn.fatal "C get_next not implemented"

include Pseudo.Make
    (struct
      type ins = instruction
      type pins = parsedInstruction
      type reg_arg = reg

      let rec parsed_expr_tr = function
        | Const(Constant.Concrete _) as k -> k
        | Const(Constant.Symbolic _) ->
            Warn.fatal "No constant variable allowed"
        | LoadReg _ as l -> l
        | LoadMem (l,mo) ->
            LoadMem (parsed_expr_tr l,mo)
        | Op(op,e1,e2) -> Op(op,parsed_expr_tr e1,parsed_expr_tr e2)
        | Exchange(l,e,mo) ->
            Exchange(parsed_expr_tr l,parsed_expr_tr e,mo)
        | CmpExchange(e1,e2,e3,a) ->
            CmpExchange(parsed_expr_tr e1,parsed_expr_tr e2,parsed_expr_tr e3,a)
        | Fetch(l,op,e,mo) ->
            Fetch(parsed_expr_tr l,op,parsed_expr_tr e,mo)
        | ECall (f,es) -> ECall (f,List.map ~f:parsed_expr_tr es)
        | ECas (e1,e2,e3,mo1,mo2,strong) ->
            ECas
              (parsed_expr_tr e1,parsed_expr_tr e2,parsed_expr_tr e3,
               mo1,mo2,strong)
        | TryLock(e,m) -> TryLock(parsed_expr_tr e,m)
        | IsLocked(e,m) -> IsLocked(parsed_expr_tr e,m)
        | AtomicOpReturn (loc,op,e,ret,a) ->
            AtomicOpReturn(parsed_expr_tr loc,op,parsed_expr_tr e,ret,a)
        | AtomicAddUnless(loc,a,u,retbool) ->
            AtomicAddUnless
              (parsed_expr_tr loc,parsed_expr_tr a,parsed_expr_tr u,retbool)
        | ExpSRCU(e,a) -> ExpSRCU(parsed_expr_tr e,a)

      and parsed_tr = function
        | Fence _|DeclReg _ as i -> i
        | Seq(li,b) -> Seq(List.map ~f:parsed_tr li,b)
        | If(e,it,ie) ->
            let tr_ie = match ie with
            | None -> None
            | Some ie -> Some(parsed_tr ie) in
            If(parsed_expr_tr e,parsed_tr it,tr_ie)
        | StoreReg(ot,l,e) -> StoreReg(ot,l,parsed_expr_tr e)
        | StoreMem(l,e,mo) ->
            StoreMem(parsed_expr_tr l,parsed_expr_tr e,mo)
        | Lock (e,k) -> Lock (parsed_expr_tr e,k)
        | Unlock (e,k) -> Unlock  (parsed_expr_tr e,k)
        | AtomicOp(l,op,e) -> AtomicOp(parsed_expr_tr l,op,parsed_expr_tr e)
        | InstrSRCU(e,a) -> InstrSRCU(parsed_expr_tr e,a)
        | Symb _ -> Warn.fatal "No term variable allowed"
        | PCall (f,es) -> PCall (f,List.map ~f:parsed_expr_tr es)

      let get_naccesses =

        let rec get_exp k = function
          | Const _ -> k
          | LoadReg _ -> k
          | LoadMem (e,_) -> get_exp (k+1) e
          | Op (_,e1,e2) -> get_exp (get_exp k e1) e2
          | Fetch (loc,_,e,_)
          | Exchange (loc,e,_)
          | AtomicOpReturn (loc,_,e,_,_) ->
              get_exp (get_exp (k+2) e) loc
          | AtomicAddUnless (loc,a,u,_) ->
              get_exp (get_exp (get_exp (k+2) u) a) loc
          | ECall (_,es) -> List.fold_left ~f:get_exp ~init:k es
          | CmpExchange (e1,e2,e3,_)
          | ECas (e1,e2,e3,_,_,_) ->
              let k = get_exp k e1 in
              let k = get_exp k e2 in
              get_exp k e3
          | TryLock(e,_) -> get_exp (k+1) e
          | IsLocked(e,_) -> get_exp (k+1) e
          | ExpSRCU(e,_) ->  get_exp (k+1) e in

        let rec get_rec k = function
          | Fence _|Symb _ | DeclReg _ -> k
          | Seq (seq,_) -> List.fold_left ~f:get_rec ~init:k seq
          | If (cond,ifso,ifno) ->
              let k = get_exp k cond in
              get_opt (get_rec k ifso) ifno
          | StoreReg (_,_,e) -> get_exp k e
          | StoreMem (loc,e,_)
          | AtomicOp(loc,_,e) -> get_exp (get_exp k loc) e
          | Lock (e,_)|Unlock (e,_) -> get_exp (k+1) e
          | InstrSRCU(e,_) -> get_exp (k+1) e
          | PCall (_,es) ->  List.fold_left ~f:get_exp ~init:k es

        and get_opt k = function
          | None -> k
          | Some i -> get_rec k i in

        fun i -> get_rec 0 i


      let fold_labels acc _f _ins = acc
      let map_labels _f ins = ins
    end)

let get_macro _s = assert false

(* C specific macros *)

type macro =
  | EDef of string * string list * expression
  | PDef of string * string list * instruction

type env_macro =
  { expr : (string list * expression) String.Map.t ;
    proc : (string list * instruction) String.Map.t ;
    args : expression String.Map.t ; }

let env_empty =
  {
   expr = String.Map.empty;
   proc = String.Map.empty;
   args = String.Map.empty;
 }

let add m env =  match m with
| EDef (f,args,e) ->
    { env with expr = String.Map.add_exn env.expr ~key:f ~data:(args,e) ; }
| PDef (f,args,body) ->
    { env with proc = String.Map.add_exn env.proc ~key:f ~data:(args,body) ; }

let find_macro f env =
  match String.Map.find env f with
  | Some x -> x
  | None -> Warn.user_error "Unknown macro %s" f

let rec build_frame f tr xs es = match xs,es with
| [],[] -> String.Map.empty
| x::xs,e::es -> String.Map.add_exn (build_frame f tr xs es) ~key:x ~data:(tr e)
| _,_ -> Warn.user_error "Argument mismatch for macro %s" f


let rec subst_expr env e = match e with
| LoadReg r ->
  Option.value ~default:e (String.Map.find env.args r)
| LoadMem (loc,mo) -> LoadMem (subst_expr env loc,mo)
| Const _ -> e
| Op (op,e1,e2) -> Op (op,subst_expr env e1,subst_expr env e2)
| Exchange (loc,e,mo) ->  Exchange (subst_expr env loc,subst_expr env e,mo)
| CmpExchange (e1,e2,e3,a) ->
    CmpExchange (subst_expr env e1,subst_expr env e2,subst_expr env e3,a)
| Fetch (loc,op,e,mo) -> Fetch (subst_expr env loc,op,subst_expr env e,mo)
| ECall (f,es) ->
    let xs,e = find_macro f env.expr in
    let frame = build_frame f (subst_expr env) xs es in
    subst_expr { env with args = frame; } e
| ECas (e1,e2,e3,mo1,mo2,strong) ->
    let e1 = subst_expr env e1
    and e2 = subst_expr env e2
    and e3 = subst_expr env e3 in
    ECas (e1,e2,e3,mo1,mo2,strong)
| TryLock (e,m) -> TryLock(subst_expr env e,m)
| IsLocked (e,m) -> IsLocked(subst_expr env e,m)
| AtomicOpReturn (loc,op,e,ret,a) ->
    AtomicOpReturn (subst_expr env loc,op,subst_expr env e,ret,a)
| AtomicAddUnless (loc,a,u,retbool) ->
    AtomicAddUnless
      (subst_expr env loc,subst_expr env a,subst_expr env u,retbool)
| ExpSRCU(e,a) -> ExpSRCU(subst_expr env e,a)

let rec subst env i = match i with
| Fence _|Symb _|DeclReg _ -> i
| Seq (is,b) -> Seq (List.map ~f:(subst env) is,b)
| If (c,ifso,None) ->
    If (subst_expr env c,subst env ifso,None)
| If (c,ifso,Some ifno) ->
    If (subst_expr env c,subst env ifso,Some (subst env ifno))
| StoreReg (ot,r,e) ->
    let e = subst_expr env e in begin
      match String.Map.find env.args r with
      | Some (LoadReg r) -> StoreReg (ot,r,e)
      | Some (LoadMem (loc,mo)) -> StoreMem (loc,e,mo)
      | Some e ->
        Warn.user_error
          "Bad lvalue '%s' while substituting macro argument %s"
          (dump_expr e) r
      | None -> StoreReg (ot,r,e)
    end
| StoreMem (loc,e,mo) ->
    StoreMem (subst_expr env loc,subst_expr env e,mo)
| Lock (loc,k) -> Lock (subst_expr env loc,k)
| Unlock (loc,k) -> Unlock (subst_expr env loc,k)
| AtomicOp (loc,op,e) -> AtomicOp(subst_expr env loc,op,subst_expr env e)
| InstrSRCU (e,a) -> InstrSRCU(subst_expr env e,a)
| PCall (f,es) ->
    let xs,body = find_macro f env.proc in
    let frame = build_frame f (subst_expr env) xs es in
    subst { env with args = frame; } body

let expand ms = match ms with
| [] -> Misc.identity
| _  ->
    let env = List.fold_left ~f:(fun e m -> add m e) ~init:env_empty ms in
    pseudo_map (subst env)
