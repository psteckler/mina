open Core_kernel
open Mina_base
open Bit_catchup_state

module Data = struct
  open Substate

  type t = transition_meta

  let merge a b =
    if Mina_numbers.Length.(a.blockchain_length < b.blockchain_length) then a
    else b
end

module Dsu = Dsu.Make (State_hash) (Data)

let is_status_processed ~state_functions =
  let viewer = function
    | { Substate.status = Processed _; _ } ->
        true
    | _ ->
        false
  in
  Fn.compose
    (Option.value ~default:false)
    (Substate.view ~state_functions ~f:{ viewer })

(** [collect_unprocessed top_state] collects unprocessed transitions from
    the top state (inclusive) down the ancestry chain while:
  
    1. [predicate] returns [(`Take _, `Continue true)]
    and
    2. Have same state level as [top_state]

    States with [Processed] status are skipped through.

    Returned list of states is in the parent-first order.

    Only states for which [predicate] returned [(`Take true, `Continue_)] are collected.
    State for which [(`Take true, `Continue false)] was returned by [predicate] will be taken.

    Complexity of this funciton is [O(n)] for [n] being the number of
    states returned plus the number of states for which [`Take false] was returned.
*)
let collect_unprocessed (type state_t)
    ?(predicate = { Substate.viewer = (fun _ -> (`Take true, `Continue true)) })
    ~state_functions ~(transition_states : state_t Substate.transition_states)
    ~dsu top_state =
  let (module F : Substate.State_functions with type state_t = state_t) =
    state_functions
  in
  let (Substate.Transition_states ((module Transition_states), states)) =
    transition_states
  in
  let viewer subst =
    match subst.Substate.status with
    | Substate.Processed _ ->
        (`Take true, `Continue false)
    | _ ->
        predicate.Substate.viewer subst
  in
  let rec go res state =
    let collected =
      Substate.collect_states ~predicate:{ viewer } ~state_functions
        ~transition_states state
    in
    match collected with
    | bottom_state :: rest_states
      when is_status_processed ~state_functions bottom_state ->
        let key = (F.transition_meta bottom_state).state_hash in
        Option.value ~default:[]
        @@ let%bind.Option ancestor = Dsu.get ~key dsu in
           let%map.Option parent =
             Transition_states.find states ancestor.parent_state_hash
           in
           go (rest_states :: res) parent
    | _ ->
        collected :: res
  in
  List.concat @@ go [] top_state

(** [next_unprocessed top_state] finds next unprocessed transition of the same state level
    from the top state (inclusive) down the ancestry chain while.

    This function has quasi-constant complexity.
*)
let next_unprocessed ~state_functions ~transition_states ~dsu top_state =
  let viewer _ = (`Take true, `Continue false) in
  List.hd
  @@ collect_unprocessed ~predicate:{ viewer } ~state_functions
       ~transition_states ~dsu top_state

(** [collect_to_in_progress top_state] collects unprocessed transitions from
    the top state (inclusive) down the ancestry chain while:
  
    1. Transitions are not in [Substate.Processing (Substate.In_progress _)] state
    and
    2. Have same state level as [top_state]

    First encountered [Substate.Processing (Substate.In_progress _)] transition (if any)
    is also included in the result. Returned list of states is in the parent-first order.

    Complexity of this funciton is [O(n)] for [n] being the size of the returned list.
*)
let collect_to_in_progress ~state_functions ~transition_states ~dsu top_state =
  let viewer = function
    | { Substate.status = Processing (In_progress _); _ } ->
        (`Take true, `Continue false)
    | _ ->
        (`Take true, `Continue true)
  in
  collect_unprocessed ~predicate:{ viewer } ~state_functions ~transition_states
    ~dsu top_state
