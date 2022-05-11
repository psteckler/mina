open Core
open Graphql_async
module Ledger = Mina_ledger.Ledger
open Schema
open Types

type context_typ = Mina_lib.t

type t = Daemon_rpcs.Types.Status.t

let interval : (_, (Time.Span.t * Time.Span.t) option) typ =
  obj "Interval" ~fields:(fun _ ->
      [ field "start" ~typ:(non_null string)
          ~args:Arg.[]
          ~resolve:(fun _ (start, _) ->
            Time.Span.to_ms start |> Int64.of_float |> Int64.to_string)
      ; field "stop" ~typ:(non_null string)
          ~args:Arg.[]
          ~resolve:(fun _ (_, end_) ->
            Time.Span.to_ms end_ |> Int64.of_float |> Int64.to_string)
      ])

let histogram : (_, Perf_histograms.Report.t option) typ =
  obj "Histogram" ~fields:(fun _ ->
      let open Reflection.Shorthand in
      List.rev
      @@ Perf_histograms.Report.Fields.fold ~init:[]
           ~values:(id ~typ:Schema.(non_null (list (non_null int))))
           ~intervals:(id ~typ:(non_null (list (non_null interval))))
           ~underflow:nn_int ~overflow:nn_int)

module Rpc_timings = Daemon_rpcs.Types.Status.Rpc_timings
module Rpc_pair = Rpc_timings.Rpc_pair

let rpc_pair : (_, Perf_histograms.Report.t option Rpc_pair.t option) typ =
  let h = Reflection.Shorthand.id ~typ:histogram in
  obj "RpcPair" ~fields:(fun _ ->
      List.rev @@ Rpc_pair.Fields.fold ~init:[] ~dispatch:h ~impl:h)

let rpc_timings : (_, Rpc_timings.t option) typ =
  let fd = Reflection.Shorthand.id ~typ:(non_null rpc_pair) in
  obj "RpcTimings" ~fields:(fun _ ->
      List.rev
      @@ Rpc_timings.Fields.fold ~init:[] ~get_staged_ledger_aux:fd
           ~answer_sync_ledger_query:fd ~get_ancestry:fd
           ~get_transition_chain_proof:fd ~get_transition_chain:fd)

module Histograms = Daemon_rpcs.Types.Status.Histograms

let histograms : (_, Histograms.t option) typ =
  let h = Reflection.Shorthand.id ~typ:histogram in
  obj "Histograms" ~fields:(fun _ ->
      let open Reflection.Shorthand in
      List.rev
      @@ Histograms.Fields.fold ~init:[]
           ~rpc_timings:(id ~typ:(non_null rpc_timings))
           ~external_transition_latency:h ~accepted_transition_local_latency:h
           ~accepted_transition_remote_latency:h ~snark_worker_transition_time:h
           ~snark_worker_merge_time:h)

let consensus_configuration : (_, Consensus.Configuration.t option) typ =
  obj "ConsensusConfiguration" ~fields:(fun _ ->
      let open Reflection.Shorthand in
      List.rev
      @@ Consensus.Configuration.Fields.fold ~init:[] ~delta:nn_int ~k:nn_int
           ~slots_per_epoch:nn_int ~slot_duration:nn_int ~epoch_duration:nn_int
           ~acceptable_network_delay:nn_int ~genesis_state_timestamp:nn_time)

module Peer = struct
  let peer : (_, Network_peer.Peer.Display.t option) typ =
    obj "Peer" ~fields:(fun _ ->
        let open Reflection.Shorthand in
        List.rev
        @@ Network_peer.Peer.Display.Fields.fold ~init:[] ~host:nn_string
             ~libp2p_port:nn_int ~peer_id:nn_string)

  type ('host, 'libp2p_port, 'peer_id) r =
    { host : 'host; libp2p_port : 'libp2p_port; peer_id : 'peer_id }

  (** The following would likely be generated by a ppx *)

  type _ query =
    | Empty : (unit, unit, unit) r query
    | Host :
        { s : (unit, 'libp2p_port, 'peer_id) r query }
        -> (string, 'libp2p_port, 'peer_id) r query
    | Libp2p_port :
        { s : ('host, unit, 'peer_id) r query }
        -> ('host, int, 'peer_id) r query
    | Peer_id :
        { s : ('host, 'libp2p_port, unit) r query }
        -> ('host, 'libp2p_port, string) r query

  let string_of_query query =
    let rec build_fields : type a. a query -> string list = function
      | Empty ->
          []
      | Host { s; _ } ->
          "host" :: build_fields s
      | Libp2p_port { s; _ } ->
          "libp2p_port" :: build_fields s
      | Peer_id { s; _ } ->
          "peer_id" :: build_fields s
    in
    Stdlib.String.concat " " @@ build_fields query

  let rec response_of_json_non_null : type a. a query -> Yojson.Basic.t -> a =
   fun query json ->
    match query with
    | Empty ->
        { host = (); libp2p_port = (); peer_id = () }
    | Host { s } ->
        { (response_of_json_non_null s json) with
          host = Graphql_utils.Json.(get_string @@ get "host" json)
        }
    | Libp2p_port { s } ->
        { (response_of_json_non_null s json) with
          libp2p_port = Graphql_utils.Json.(get_int @@ get "libp2p_port" json)
        }
    | Peer_id { s } ->
        { (response_of_json_non_null s json) with
          peer_id = Graphql_utils.Json.(get_string @@ get "peer_id" json)
        }

  let response_of_json : type a. a query -> Yojson.Basic.t -> a option =
   fun query json ->
    match json with
    | `Null ->
        None
    | _ ->
        Some (response_of_json_non_null query json)
end

let addrs_and_ports : (_, Node_addrs_and_ports.Display.t option) typ =
  obj "AddrsAndPorts" ~fields:(fun _ ->
      let open Reflection.Shorthand in
      List.rev
      @@ Node_addrs_and_ports.Display.Fields.fold ~init:[]
           ~external_ip:nn_string ~bind_ip:nn_string ~client_port:nn_int
           ~libp2p_port:nn_int ~peer:(id ~typ:Peer.peer))

let metrics : (_, Daemon_rpcs.Types.Status.Metrics.t option) typ =
  obj "Metrics" ~fields:(fun _ ->
      let open Reflection.Shorthand in
      List.rev
      @@ Daemon_rpcs.Types.Status.Metrics.Fields.fold ~init:[]
           ~block_production_delay:nn_int_list
           ~transaction_pool_diff_received:nn_int
           ~transaction_pool_diff_broadcasted:nn_int
           ~transactions_added_to_pool:nn_int ~transaction_pool_size:nn_int)

let t : (_, Daemon_rpcs.Types.Status.t option) typ =
  obj "DaemonStatus" ~fields:(fun _ ->
      let open Reflection.Shorthand in
      List.rev
      @@ Daemon_rpcs.Types.Status.Fields.fold ~init:[] ~num_accounts:int
           ~catchup_status:nn_catchup_status ~chain_id:nn_string
           ~next_block_production:(id ~typ:block_producer_timing)
           ~blockchain_length:int ~uptime_secs:nn_int ~ledger_merkle_root:string
           ~state_hash:string ~commit_id:nn_string ~conf_dir:nn_string
           ~peers:(id ~typ:(non_null (list (non_null Peer.peer))))
           ~user_commands_sent:nn_int ~snark_worker:string
           ~snark_work_fee:nn_int
           ~sync_status:(id ~typ:(non_null Sync_status_gql.sync_status))
           ~block_production_keys:
             (id ~typ:(non_null @@ list (non_null Schema.string)))
           ~coinbase_receiver:(id ~typ:Schema.string)
           ~histograms:(id ~typ:histograms)
           ~consensus_time_best_tip:(id ~typ:consensus_time)
           ~global_slot_since_genesis_best_tip:int
           ~consensus_time_now:(id ~typ:Schema.(non_null consensus_time))
           ~consensus_mechanism:nn_string
           ~addrs_and_ports:(id ~typ:(non_null addrs_and_ports))
           ~consensus_configuration:(id ~typ:(non_null consensus_configuration))
           ~highest_block_length_received:nn_int
           ~highest_unvalidated_block_length_received:nn_int
           ~metrics:(id ~typ:(non_null metrics)))
