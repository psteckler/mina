open Core
open Import
open Types
open Pickles_types
open Hlist
open Snarky_backendless.Request
open Common
open Backend

module Wrap = struct
  module type S = sig
    type max_num_parents

    type max_local_max_branchings

    open Impls.Wrap
    open Wrap_main_inputs
    open Snarky_backendless.Request

    type _ t +=
      | Evals :
          ( (Field.Constant.t array Dlog_plonk_types.Evals.t * Field.Constant.t)
            Tuple_lib.Double.t
          , max_num_parents )
          Vector.t
          t
      | Step_accs : (Tock.Inner_curve.Affine.t, max_num_parents) Vector.t t
      | Old_bulletproof_challenges :
          max_local_max_branchings H1.T(Challenges_vector.Constant).t t
      | Proof_state :
          ( ( ( Challenge.Constant.t
              , Challenge.Constant.t Scalar_challenge.t
              , Field.Constant.t Shifted_value.t
              , ( Challenge.Constant.t Scalar_challenge.t
                  Bulletproof_challenge.t
                , Tock.Rounds.n )
                Vector.t
              , Digest.Constant.t
              , bool )
              Types.Pairing_based.Proof_state.Per_proof.In_circuit.t
            , max_num_parents )
            Vector.t
          , Digest.Constant.t )
          Types.Pairing_based.Proof_state.t
          t
      | Messages :
          ( Tock.Inner_curve.Affine.t
          , Tock.Inner_curve.Affine.t Or_infinity.t )
          Dlog_plonk_types.Messages.t
          t
      | Openings_proof :
          ( Tock.Inner_curve.Affine.t
          , Tick.Field.t )
          Dlog_plonk_types.Openings.Bulletproof.t
          t
  end

  type ('max_num_parents, 'ml) t =
    (module S
       with type max_num_parents = 'max_num_parents
        and type max_local_max_branchings = 'ml)

  let create : type max_num_parents ml. unit -> (max_num_parents, ml) t =
   fun () ->
    let module R = struct
      type nonrec max_num_parents = max_num_parents

      type nonrec max_local_max_branchings = ml

      open Snarky_backendless.Request

      type 'a vec = ('a, max_num_parents) Vector.t

      type _ t +=
        | Evals :
            (Tock.Field.t array Dlog_plonk_types.Evals.t * Tock.Field.t)
            Tuple_lib.Double.t
            vec
            t
        | Step_accs : Tock.Inner_curve.Affine.t vec t
        | Old_bulletproof_challenges :
            max_local_max_branchings H1.T(Challenges_vector.Constant).t t
        | Proof_state :
            ( ( ( Challenge.Constant.t
                , Challenge.Constant.t Scalar_challenge.t
                , Tock.Field.t Shifted_value.t
                , ( Challenge.Constant.t Scalar_challenge.t
                    Bulletproof_challenge.t
                  , Tock.Rounds.n )
                  Vector.t
                , Digest.Constant.t
                , bool )
                Types.Pairing_based.Proof_state.Per_proof.In_circuit.t
              , max_num_parents )
              Vector.t
            , Digest.Constant.t )
            Types.Pairing_based.Proof_state.t
            t
        | Messages :
            ( Tock.Inner_curve.Affine.t
            , Tock.Inner_curve.Affine.t Or_infinity.t )
            Dlog_plonk_types.Messages.t
            t
        | Openings_proof :
            ( Tock.Inner_curve.Affine.t
            , Tick.Field.t )
            Dlog_plonk_types.Openings.Bulletproof.t
            t
    end in
    (module R)
end

module Step = struct
  open Zexe_backend

  module type S = sig
    type statement

    type prev_values

    (* TODO: As an optimization this can be the local branching size *)
    type max_num_parents

    type prev_num_parentss

    type local_branches

    type _ t +=
      | Proof_with_datas :
          ( prev_values
          , prev_num_parentss
          , local_branches )
          H3.T(Per_proof_witness.Constant).t
          t
      | Wrap_index : Tock.Curve.Affine.t array Plonk_verification_key_evals.t t
      | App_state : statement t
  end

  let create
      : type prev_num_parentss local_branches statement prev_values max_num_parents.
         unit
      -> (module S
            with type prev_num_parentss = prev_num_parentss
             and type local_branches = local_branches
             and type statement = statement
             and type prev_values = prev_values
             and type max_num_parents = max_num_parents) =
   fun () ->
    let module R = struct
      type nonrec max_num_parents = max_num_parents

      type nonrec statement = statement

      type nonrec prev_values = prev_values

      type nonrec prev_num_parentss = prev_num_parentss

      type nonrec local_branches = local_branches

      type _ t +=
        | Proof_with_datas :
            ( prev_values
            , prev_num_parentss
            , local_branches )
            H3.T(Per_proof_witness.Constant).t
            t
        | Wrap_index :
            Tock.Curve.Affine.t array Plonk_verification_key_evals.t t
        | App_state : statement t
    end in
    (module R)
end
