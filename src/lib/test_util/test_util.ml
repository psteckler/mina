[%%import "/src/config.mlh"]

open Core_kernel

[%%ifdef consensus_mechanism]

[%%error "foobar"]

open Fold_lib
open Snark_params.Tick

let triple_string trips =
  let to_string b = if b then "1" else "0" in
  String.concat ~sep:" "
    (List.map trips ~f:(fun (b1, b2, b3) ->
         to_string b1 ^ to_string b2 ^ to_string b3 ) )

let checked_to_unchecked typ1 typ2 checked input =
  let open Impl in
  let (), checked_result =
    run_and_check
      (let%bind input = exists typ1 ~compute:(As_prover.return input) in
       let%map result = checked input in
       As_prover.read typ2 result )
      ()
    |> Or_error.ok_exn
  in
  checked_result

let test_to_triples typ fold var_to_triples input =
  let open Impl in
  let (), checked =
    run_and_check
      (let%bind input = exists typ ~compute:(As_prover.return input) in
       let%map result = var_to_triples input in
       As_prover.all
         (List.map result
            ~f:(As_prover.read (Typ.tuple3 Boolean.typ Boolean.typ Boolean.typ)) )
      )
      ()
    |> Or_error.ok_exn
  in
  let unchecked = Fold.to_list (fold input) in
  if not ([%equal: (bool * bool * bool) list] checked unchecked) then
    failwithf
      !"Got %s (%d)\nexpected %s (%d)"
      (triple_string checked) (List.length checked) (triple_string unchecked)
      (List.length unchecked) ()

let test_equal ?(equal = Poly.( = )) typ1 typ2 checked unchecked input =
  let checked_result = checked_to_unchecked typ1 typ2 checked input in
  assert (equal checked_result (unchecked input))

[%%endif]

let arbitrary_string ~len =
  String.init (Random.int len) ~f:(fun _ ->
      Char.of_int_exn (Random.int_incl 0 255) )

let with_randomness r f =
  let s = Caml.Random.get_state () in
  Random.init r ;
  try
    let x = f () in
    Caml.Random.set_state s ; x
  with e -> Caml.Random.set_state s ; raise e

(** utility function to print digests to put in tests, see `check_serialization' below *)
let print_digest digest = printf "\"" ; printf "%s" digest ; printf "\"\n%!"

(** use this function to test Bin_prot serialization of types *)
let check_serialization (type t) (module M : Binable.S with type t = t) (t : t)
    known_good_digest =
  (* serialize value *)
  let sz = M.bin_size_t t in
  let buf = Bin_prot.Common.create_buf sz in
  ignore (M.bin_write_t buf ~pos:0 t : int) ;
  let bytes = Bytes.create sz in
  Bin_prot.Common.blit_buf_bytes buf bytes ~len:sz ;
  (* compute MD5 digest of serialization *)
  let digest = Md5.digest_bytes bytes |> Md5.to_hex in
  let result = String.equal digest known_good_digest in
  if not result then (
    printf "Expected digest: " ;
    print_digest known_good_digest ;
    printf "Got digest:      " ;
    print_digest digest ) ;
  result
