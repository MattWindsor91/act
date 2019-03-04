open Core
open Utils

module M = struct
  type t =
    { c_path    : Fpath.t
    ; litc_path : Fpath.t
    ; asm_path  : Fpath.t
    ; lita_path : Fpath.t
    ; herd_path : Fpath.t
    } [@@deriving fields]
end
include M

module File = struct
  type ps = t

  type t =
    { basename   : string
    ; c_path     : Fpath.t
    ; litc_path  : Fpath.t
    ; asm_path   : Fpath.t
    ; lita_path  : Fpath.t
    ; herdc_path : Fpath.t
    ; herda_path : Fpath.t
    } [@@deriving fields]

  let make ps (name : string) =
    Fpath.
    { basename   = name
    ; c_path     = M.c_path ps    / name + ".c"
    ; litc_path  = M.litc_path ps / name + ".litmus"
    ; asm_path   = M.asm_path  ps / name + ".s"
    ; lita_path  = M.lita_path ps / name + ".s.litmus"
    ; herdc_path = M.herd_path ps / name + ".herd.txt"
    ; herda_path = M.herd_path ps / name + ".s.herd.txt"
    }
  ;;
end


type ent_type =
  | File
  | Dir
  | Nothing
  | Unknown
;;

let get_ent_type (path : string) : ent_type =
  match Sys.file_exists path with
  | `No -> Nothing
  | `Unknown -> Unknown
  | `Yes ->
     match Sys.is_directory path with
     | `No -> File
     | `Unknown -> Unknown
     | `Yes -> Dir

(** [mkdir path] tries to make a directory at path [path].
    If [path] exists and is a directory, it does nothing.
    If [path] exists but is a file, or another error occurred, it returns
    an error message. *)
let mkdir (path : string) =
  let open Or_error in
  match get_ent_type path with
  | Dir -> Result.ok_unit
  | File -> error_s [%message "path exists, but is a file" ~path]
  | Unknown -> error_s [%message "couldn't determine whether path already exists" ~path]
  | Nothing -> Or_error.try_with (fun () -> Unix.mkdir path)
;;

let subpaths (path : Fpath.t) : string list =
  List.map ~f:My_filename.concat_list (Travesty.T_list.prefixes (Fpath.segs path))
;;

let mkdir_p (path : Fpath.t) =
  Or_error.all_unit (List.map ~f:mkdir (subpaths path))
;;

let all_paths (ps : t) : (string, Fpath.t) List.Assoc.t =
  let to_pair fld = (Field.name fld, Field.get fld ps) in
  Fields.to_list
    ~c_path:to_pair
    ~litc_path:to_pair
    ~asm_path:to_pair
    ~lita_path:to_pair
    ~herd_path:to_pair
;;

let mkdirs ps =
  Or_error.(
    tag ~tag:"Couldn't make directories"
      (try_with_join
         ( fun () ->
             Or_error.all_unit
               (List.map ~f:(Fn.compose mkdir_p snd) (all_paths ps))
         )
      )
  )
;;

let make_id_path init id =
  let segs = Id.to_string_list id in
  List.fold ~init ~f:(Fpath.add_seg) segs
;;

let%expect_test "make_id_path: folds in correct direction" =
  let id = Id.of_string "foo.bar.baz" in
  let init = Fpath.v "." in
  Io.print_bool
    (Fpath.equal
       (make_id_path init id)
       Fpath.(init / "foo" / "bar" / "baz")
    );
  [%expect {| true |}]
;;

(** [make_input_path in_root subdir mode] produces a sub-path of
   [in_root] that denotes where act expects to find a particular type
   of input.

   - When [mode] is [`Separate], act expects the input to be separated
   into subdirectories, and the resulting input path is
   [in_root/subdir].
   - When [mode] is [`Together], act expects the input to be in one
   directory, namely [in_root], and the resulting input path is
   [in_root]. *)
let make_input_path
    (in_root : Fpath.t) (subdir : string)
    (mode : [< `Separate | `Together ])
  : Fpath.t = match mode with
  | `Together -> in_root
  | `Separate -> Fpath.(in_root / subdir)
;;

let make id
    ~(in_root : Fpath.t) ~(out_root : Fpath.t)
    ~(input_mode : [< `Separate | `Together ]) =
  let id_path = make_id_path out_root id in
  Fpath.
  { c_path    = make_input_path in_root "C" input_mode
  ; litc_path = make_input_path in_root "Litmus" input_mode
  ; asm_path  = id_path / "asm"
  ; lita_path = id_path / "litmus"
  ; herd_path = id_path / "herd"
  }
;;

let%test_module "all_paths of make" = (module struct
  let run_test ~input_mode =
    let id = Id.of_string "foo.bar.baz" in
    let ps = make id ~in_root:(Fpath.v "inputs") ~out_root:(Fpath.v "outputs") ~input_mode in
    let all = all_paths ps in
    let all_str = List.Assoc.map ~f:Fpath.segs all in
    Format.printf "@[%a@]@."
      Sexp.pp_hum
      [%sexp (all_str : (string, string list) List.Assoc.t)]
  ;;

  let%expect_test "all_paths of make (separate mode)" =
    run_test ~input_mode:`Separate;
    [%expect {|
    ((c_path (inputs C)) (litc_path (inputs Litmus))
     (asm_path (outputs foo bar baz asm))
     (lita_path (outputs foo bar baz litmus))
     (herd_path (outputs foo bar baz herd))) |}]
  ;;

  let%expect_test "all_paths of make (together mode)" =
    run_test ~input_mode:`Together;
    [%expect {|
    ((c_path (inputs)) (litc_path (inputs)) (asm_path (outputs foo bar baz asm))
     (lita_path (outputs foo bar baz litmus))
     (herd_path (outputs foo bar baz herd))) |}]
  ;;
end)

let make_and_mkdirs id ~in_root ~out_root ~input_mode =
  let paths = make id ~in_root ~out_root ~input_mode in
  Or_error.(mkdirs paths >>= (fun _ -> return paths))
;;

let pp : t Fmt.t =
  let p f (k, v) =
    My_format.pp_kv f k String.pp (My_filename.concat_list v)
  in
  Fmt.(
    using (fun ps -> (List.Assoc.map ~f:Fpath.segs (all_paths ps)))
    (vbox (list ~sep:cut p))
  )
;;
