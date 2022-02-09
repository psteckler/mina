open Core_kernel
open Fieldslib

module Iso = struct
  type ('row, 'a, 'b) t =
    < map : ('a -> 'b) ref ; contramap : ('b -> 'a) ref ; .. > as 'row
end

module Graphql_args_raw = struct
  module Make (Schema : Graphql_intf.Schema) = struct
    module Input = struct
      type ('row, 'ty) t =
        < graphql_arg : (unit -> 'ty Schema.Arg.arg_typ) ref
        ; nullable_graphql_arg : (unit -> 'ty option Schema.Arg.arg_typ) ref
        ; .. >
        as
        'row
    end

    module Acc = struct
      module T = struct
        type ('ty, 'fields) t_inner =
          { graphql_arg_fields : ('ty, 'fields) Schema.Arg.arg_list
          ; graphql_arg_coerce : 'fields
          }

        type 'ty t = Init | Acc : ('ty, 'fields) t_inner -> 'ty t
      end

      type ('row, 'ty) t =
        < graphql_arg_accumulator : 'ty T.t ref ; .. > as 'row
    end

    module Creator = struct
      type 'row t = < .. > as 'row
    end

    module Output = struct
      type 'row t = < .. > as 'row
    end

    let add_field (type f ty) :
           ('f_row, f) Input.t
        -> ([< `Read | `Set_and_create ], ty, f) Field.t_with_perm
        -> ('row, ty) Acc.t
        -> ('row Creator.t -> f) * ('row_after, ty) Acc.t =
     fun f_input field acc ->
      let ref_as_pipe = ref None in
      let arg =
        Schema.Arg.arg (Field.name field) ~typ:(!(f_input#graphql_arg) ())
      in
      let () =
        let inner_acc = acc#graphql_arg_accumulator in
        match !inner_acc with
        | Init ->
            inner_acc :=
              Acc
                { graphql_arg_coerce =
                    (fun x ->
                      ref_as_pipe := Some x ;
                      !(acc#graphql_creator) acc)
                ; graphql_arg_fields = [ arg ]
                }
        | Acc { graphql_arg_fields; graphql_arg_coerce } -> (
            match graphql_arg_fields with
            | [] ->
                inner_acc :=
                  Acc
                    { graphql_arg_coerce =
                        (fun x ->
                          ref_as_pipe := Some x ;
                          !(acc#graphql_creator) acc)
                    ; graphql_arg_fields = [ arg ]
                    }
            | _ ->
                inner_acc :=
                  Acc
                    { graphql_arg_coerce =
                        (fun x ->
                          ref_as_pipe := Some x ;
                          graphql_arg_coerce)
                    ; graphql_arg_fields = arg :: graphql_arg_fields
                    } )
      in
      ((fun _creator_input -> Option.value_exn !ref_as_pipe), acc)

    let finish ?doc ~name (type ty) :
        (('row, ty) Input.t -> ty) * ('row, ty) Acc.t -> 'row Output.t =
     fun (creator, acc) ->
      acc#graphql_creator := creator ;
      (acc#graphql_arg :=
         fun () ->
           match !(acc#graphql_arg_accumulator) with
           | Init ->
               failwith "Graphql args need at least one field"
           | Acc { graphql_arg_fields; graphql_arg_coerce } ->
               Schema.Arg.(
                 obj ?doc name ~fields:graphql_arg_fields
                   ~coerce:graphql_arg_coerce
                 |> non_null)) ;
      (acc#nullable_graphql_arg :=
         fun () ->
           match !(acc#graphql_arg_accumulator) with
           | Init ->
               failwith "Graphql args need at least one field"
           | Acc { graphql_arg_fields; graphql_arg_coerce } ->
               Schema.Arg.(
                 obj ?doc name ~fields:graphql_arg_fields
                   ~coerce:graphql_arg_coerce)) ;
      acc

    let int obj =
      (obj#graphql_arg := fun () -> Schema.Arg.(non_null int)) ;
      obj#map := Fn.id ;
      obj#graphql_arg_accumulator := !(obj#graphql_arg_accumulator) ;
      (obj#nullable_graphql_arg := fun () -> Schema.Arg.int) ;
      obj

    let string obj =
      (obj#graphql_arg := fun () -> Schema.Arg.(non_null string)) ;
      obj#map := Fn.id ;
      obj#graphql_arg_accumulator := !(obj#graphql_arg_accumulator) ;
      (obj#nullable_graphql_arg := fun () -> Schema.Arg.string) ;
      obj

    let bool obj =
      (obj#graphql_arg := fun () -> Schema.Arg.(non_null bool)) ;
      obj#map := Fn.id ;
      obj#graphql_arg_accumulator := !(obj#graphql_arg_accumulator) ;
      (obj#nullable_graphql_arg := fun () -> Schema.Arg.bool) ;
      obj

    let list x obj : (_, 'input_type list) Input.t =
      (obj#graphql_arg :=
         fun () -> Schema.Arg.(non_null (list (!(x#graphql_arg) ())))) ;
      obj#map := List.map ~f:!(x#map) ;
      obj#graphql_arg_accumulator := !(x#graphql_arg_accumulator) ;
      (obj#nullable_graphql_arg :=
         fun () -> Schema.Arg.(list (!(x#graphql_arg) ()))) ;
      obj

    let option (x : (_, 'input_type) Input.t) obj =
      obj#graphql_arg := !(x#nullable_graphql_arg) ;
      (obj#nullable_graphql_arg :=
         fun () -> failwith "you can't double option in graphql args") ;
      obj#map := Option.map ~f:!(x#map) ;
      obj#graphql_arg_accumulator := !(x#graphql_arg_accumulator) ;
      obj

    (*
    let map ~(f : 'c -> 'd) (x : ('input_type, 'b, 'c, 'nullable) Input.t) obj :
        ('input_type, _, 'd, _) Input.t =
      obj#graphql_fields := !(x#graphql_fields) ;
      (obj#contramap := fun a -> !(x#contramap) (f a)) ;
      obj#nullable_graphql_fields := !(x#nullable_graphql_fields) ;
      obj#graphql_fields_accumulator := !(x#graphql_fields_accumulator) ;
      obj
      *)
  end
end

module Graphql_fields_raw = struct
  module Make (Schema : Graphql_intf.Schema) = struct
    module Input = struct
      module T = struct
        type 'input_type t =
          { run : 'ctx. unit -> ('ctx, 'input_type) Schema.typ }
      end

      type ('input_type, 'a, 'nullable) t =
        < graphql_fields : 'input_type T.t ref
        ; nullable_graphql_fields : 'nullable T.t ref
        ; .. >
        as
        'a
    end

    module Accumulator = struct
      module T = struct
        type 'input_type t =
          { run :
              'ctx 'row1 'output_type.    ( 'row1
                                          , 'input_type
                                          , 'output_type )
                                          Iso.t
              -> ('ctx, 'output_type) Schema.field
          }
      end

      (** thunks generating the schema in reverse *)
      type ('input_type, 'a, 'nullable) t =
        < graphql_fields_accumulator : 'input_type T.t list ref ; .. > as 'a
        constraint
          ('input_type, 'a, 'nullable) t =
          ('input_type, 'a, 'nullable) Input.t
    end

    module Output = struct
      module T = struct
        type 'input_type t =
          { run :
              'ctx 'row1 'output_type.    ( 'row1
                                          , 'input_type
                                          , 'output_type )
                                          Iso.t
              -> ('ctx, 'output_type) Schema.typ
          }
      end

      type ('input_type, 'a, 'nullable) t =
        < graphql_output : 'input_type T.t ref ; .. > as 'a
        constraint
          ('input_type, 'a, 'nullable) t =
          ('input_type, 'a, 'nullable) Input.t
    end

    let add_field (type input_type orig nullable nullable') :
           (orig, 'a, nullable) Input.t
        -> ( [< `Read | `Set_and_create ]
           , input_type
           , orig )
           Fieldslib.Field.t_with_perm
        -> (input_type, 'row2, nullable') Accumulator.t
        -> (_ -> orig) * (input_type, 'row2, nullable') Accumulator.t =
     fun t_field field acc ->
      let rest = !(acc#graphql_fields_accumulator) in
      acc#graphql_fields_accumulator :=
        { Accumulator.T.run =
            (fun iso ->
              Schema.field
                (Fields_derivers_util.name_under_to_camel field)
                ~args:Schema.Arg.[]
                ?doc:None ?deprecated:None
                ~typ:(!(t_field#graphql_fields).Input.T.run ())
                ~resolve:(fun _ x -> Field.get field (!(iso#contramap) x)))
        }
        :: rest ;
      ((fun _ -> failwith "Unused"), acc)

    (* TODO: Do we need doc and deprecated and name on finish? *)
    let finish ~name ?doc ((_creator, obj) : 'u * _ Accumulator.t) : _ Input.t =
      let obj : _ Output.t = obj in
      obj#contramap := Fn.id ;
      let graphql_fields_accumulator = !(obj#graphql_fields_accumulator) in
      let graphql_fields =
        { Input.T.run =
            (fun () ->
              Schema.obj name ?doc ~fields:(fun _ ->
                  List.rev
                  @@ List.map graphql_fields_accumulator ~f:(fun g ->
                         g.Accumulator.T.run obj))
              |> Schema.non_null)
        }
      in
      let nullable_graphql_fields =
        { Input.T.run =
            (fun () ->
              Schema.obj name ?doc ~fields:(fun _ ->
                  List.rev
                  @@ List.map graphql_fields_accumulator ~f:(fun g ->
                         g.Accumulator.T.run obj)))
        }
      in
      let graphql_output =
        { Output.T.run =
            (fun iso ->
              Schema.obj name ?doc ~fields:(fun _ ->
                  List.rev
                  @@ List.map graphql_fields_accumulator ~f:(fun g ->
                         g.Accumulator.T.run iso))
              |> Schema.non_null)
        }
      in
      obj#graphql_output := graphql_output ;
      obj#graphql_fields := graphql_fields ;
      obj#nullable_graphql_fields := nullable_graphql_fields ;
      obj

    let int obj =
      (obj#graphql_fields := Input.T.{ run = (fun () -> Schema.(non_null int)) }) ;
      obj#contramap := Fn.id ;
      obj#graphql_fields_accumulator := !(obj#graphql_fields_accumulator) ;
      (obj#nullable_graphql_fields := Input.T.{ run = (fun () -> Schema.int) }) ;
      (obj#graphql_output :=
         Output.T.{ run = (fun _ -> failwith "you cannot transform scalars") }) ;
      obj

    let string obj =
      (obj#graphql_fields :=
         Input.T.{ run = (fun () -> Schema.(non_null string)) }) ;
      obj#contramap := Fn.id ;
      obj#graphql_fields_accumulator := !(obj#graphql_fields_accumulator) ;
      (obj#nullable_graphql_fields :=
         Input.T.{ run = (fun () -> Schema.string) }) ;
      (obj#graphql_output :=
         Output.T.{ run = (fun _ -> failwith "you cannot transform scalars") }) ;
      obj

    let bool obj =
      (obj#graphql_fields :=
         Input.T.{ run = (fun () -> Schema.(non_null bool)) }) ;
      obj#contramap := Fn.id ;
      obj#graphql_fields_accumulator := !(obj#graphql_fields_accumulator) ;
      (obj#nullable_graphql_fields := Input.T.{ run = (fun () -> Schema.bool) }) ;
      (obj#graphql_output :=
         Output.T.{ run = (fun _ -> failwith "you cannot transform scalars") }) ;
      obj

    let list x obj : ('input_type list, _, _) Input.t =
      (obj#graphql_fields :=
         Input.T.
           { run =
               (fun () -> Schema.(non_null (list (!(x#graphql_fields).run ()))))
           }) ;
      obj#contramap := List.map ~f:!(x#contramap) ;
      obj#graphql_fields_accumulator := !(x#graphql_fields_accumulator) ;
      (obj#nullable_graphql_fields :=
         Input.T.
           { run = (fun () -> Schema.(list (!(x#graphql_fields).run ()))) }) ;
      (obj#graphql_output :=
         Output.T.{ run = (fun _ -> failwith "You can't transform a list") }) ;
      obj

    (* I can't get OCaml to typecheck this poperly unless we pass the same fresh function twice *)
    let option (x : ('input_type, 'b, 'nullable) Input.t) obj :
        ('input_type option, _, _) Input.t =
      obj#graphql_fields := !(x#nullable_graphql_fields) ;
      obj#nullable_graphql_fields := !(x#nullable_graphql_fields) ;
      obj#contramap := Option.map ~f:!(x#contramap) ;
      obj#graphql_fields_accumulator := !(x#graphql_fields_accumulator) ;
      (obj#graphql_output :=
         Output.T.{ run = (fun _ -> failwith "You cannot transform options") }) ;
      obj

    let contramap ~(f : 'd -> 'c) (x : ('input_type, 'b, 'nullable) Input.t) obj
        : ('input_type, _, _) Input.t =
      obj#graphql_fields := !(x#graphql_fields) ;
      (obj#contramap := fun a -> !(x#contramap) (f a)) ;
      obj#nullable_graphql_fields := !(x#nullable_graphql_fields) ;
      obj#graphql_fields_accumulator := !(x#graphql_fields_accumulator) ;
      (obj#graphql_output :=
         Output.T.{ run = (fun _ -> failwith "you cannot transform scalars") }) ;
      obj
  end
end

module IO = struct
  include Async_kernel.Deferred

  let bind x f = bind x ~f

  module Stream = struct
    type 'a t = 'a Async_kernel.Pipe.Reader.t

    let map t f =
      Async_kernel.Pipe.map' t ~f:(fun q ->
          Async_kernel.Deferred.Queue.map q ~f)

    let iter t f = Async_kernel.Pipe.iter t ~f

    let close = Async_kernel.Pipe.close_read
  end
end

module Schema = Graphql_schema.Make (IO)
module Graphql_fields = Graphql_fields_raw.Make (Schema)
module Graphql_args = Graphql_args_raw.Make (Schema)

(** Convert this async Graphql_fields schema type into the official
      Graphql_async one. The real Graphql_async functor application *is*
      equivalent but the way the library is designed we can't actually see it so
      this boils down to an Obj.magic. *)
let typ_conv (typ : ('a, 'b) Schema.typ) : ('a, 'b) Graphql_async.Schema.typ =
  Obj.magic typ

let%test_module "Test" =
  ( module struct
    (* Pure -- just like Graphql libraries functor application *)
    module IO = struct
      type +'a t = 'a

      let bind t f = f t

      let return t = t

      module Stream = struct
        type 'a t = 'a Seq.t

        let map t f = Seq.map f t

        let iter t f = Seq.iter f t

        let close _t = ()
      end
    end

    module Schema = Graphql_schema.Make (IO)
    module Graphql_fields = Graphql_fields_raw.Make (Schema)
    module Graphql_args = Graphql_args_raw.Make (Schema)

    let introspection_query_raw =
      {graphql|
query IntrospectionQuery {
    __schema {
      queryType { name }
      mutationType { name }
      subscriptionType { name }
      types {
        ...FullType
      }
      directives {
        name
        description
        locations
        args {
          ...InputValue
        }
      }
    }
  }
  fragment FullType on __Type {
    kind
    name
    description
    fields(includeDeprecated: true) {
      name
      description
      args {
        ...InputValue
      }
      type {
        ...TypeRef
      }
      isDeprecated
      deprecationReason
    }
    inputFields {
      ...InputValue
    }
    interfaces {
      ...TypeRef
    }
    enumValues(includeDeprecated: true) {
      name
      description
      isDeprecated
      deprecationReason
    }
    possibleTypes {
      ...TypeRef
    }
  }
  fragment InputValue on __InputValue {
    name
    description
    type { ...TypeRef }
    defaultValue
  }
  fragment TypeRef on __Type {
    kind
    name
    ofType {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
        }
      }
    }
  }
|graphql}

    let introspection_query () =
      match Graphql_parser.parse introspection_query_raw with
      | Ok res ->
          res
      | Error err ->
          failwith err

    let deriver (type a b c d) () :
        < contramap : (a -> b) ref
        ; graphql_fields : c Graphql_fields.Input.T.t ref
        ; nullable_graphql_fields : d Graphql_fields.Input.T.t ref
        ; .. >
        as
        'row =
      let open Graphql_fields in
      let graphql_fields =
        ref Input.T.{ run = (fun () -> failwith "unimplemented") }
      in
      let graphql_arg = ref (fun () -> failwith "unimplemented") in
      let contramap = ref (fun _ -> failwith "unimplemented") in
      let map = ref (fun _ -> failwith "unimplemented") in
      let nullable_graphql_fields =
        ref Input.T.{ run = (fun () -> failwith "unimplemented") }
      in
      let nullable_graphql_arg = ref (fun () -> failwith "unimplemented") in
      let graphql_fields_accumulator = ref [] in
      let graphql_arg_accumulator = ref Graphql_args.Acc.T.Init in
      let graphql_creator = ref (fun _ -> failwith "unimplemented") in
      let graphql_output =
        ref Output.T.{ run = (fun _ -> failwith "unimplemented") }
      in
      object
        method graphql_fields = graphql_fields

        method graphql_arg = graphql_arg

        method contramap = contramap

        method map = map

        method nullable_graphql_fields = nullable_graphql_fields

        method nullable_graphql_arg = nullable_graphql_arg

        method graphql_fields_accumulator = graphql_fields_accumulator

        method graphql_arg_accumulator = graphql_arg_accumulator

        method graphql_creator = graphql_creator

        method graphql_output = graphql_output
      end

    let o () = deriver ()

    let hit_server (typ : _ Schema.typ) v =
      let query_top_level =
        Schema.(
          field "query" ~typ:(non_null typ)
            ~args:Arg.[]
            ~doc:"sample query"
            ~resolve:(fun _ _ -> v))
      in
      let schema =
        Schema.(schema [ query_top_level ] ~mutations:[] ~subscriptions:[])
      in
      let res = Schema.execute schema () (introspection_query ()) in
      match res with
      | Ok (`Response data) ->
          data |> Yojson.Basic.to_string
      | _ ->
          failwith "Unexpected response"

    let hit_server_args (arg_typ : 'a Schema.Arg.arg_typ) =
      let query_top_level =
        Schema.(
          field "args" ~typ:(non_null int)
            ~args:Arg.[ arg "input" ~typ:arg_typ ]
            ~doc:"sample args query"
            ~resolve:(fun _ _ _ -> 0))
      in
      let schema =
        Schema.(schema [ query_top_level ] ~mutations:[] ~subscriptions:[])
      in
      let res = Schema.execute schema () (introspection_query ()) in
      match res with
      | Ok (`Response data) ->
          (*Yojson.Basic.pretty_print Format.std_formatter data ;*)
          data |> Yojson.Basic.to_string
      | _ ->
          failwith "Unexpected response"

    module T1 = struct
      type t = { foo_hello : int option; bar : string list } [@@deriving fields]

      let _v = { foo_hello = Some 1; bar = [ "baz1"; "baz2" ] }

      let manual_typ =
        Schema.(
          obj "T1" ?doc:None ~fields:(fun _ ->
              [ field "fooHello"
                  ~args:Arg.[]
                  ~typ:int
                  ~resolve:(fun _ t -> t.foo_hello)
              ; field "bar"
                  ~args:Arg.[]
                  ~typ:(non_null (list (non_null string)))
                  ~resolve:(fun _ t -> t.bar)
              ]))

      let manual_arg_typ =
        Schema.Arg.(
          obj "T1_arg" ?doc:None
            ~fields:
              [ arg "bar" ~typ:(non_null (list (non_null string)))
              ; arg "fooHello" ~typ:int
              ]
            ~coerce:(fun bar foo_hello -> { bar; foo_hello }))

      let derived init =
        let open Graphql_fields in
        let ( !. ) x fd acc = add_field (x (o ())) fd acc in
        Fields.make_creator init
          ~foo_hello:!.(option @@ int @@ o ())
          ~bar:!.(list @@ string @@ o ())
        |> finish ~name:"T1" ?doc:None

      module Args = struct
        let derived init =
          let open Graphql_args in
          let ( !. ) x fd acc = add_field (x (o ())) fd acc in
          Fields.make_creator init
            ~foo_hello:!.(option @@ int @@ o ())
            ~bar:!.(list @@ string @@ o ())
          |> finish ~name:"T1_arg" ?doc:None
      end
    end

    let%test_unit "T1 unfold" =
      let open Graphql_args in
      let generated_arg_typ =
        let obj = T1.(option @@ Args.derived @@ o ()) (o ()) in
        !(obj#graphql_arg) ()
      in
      [%test_eq: string]
        (hit_server_args generated_arg_typ)
        (hit_server_args T1.manual_arg_typ)

    module Or_ignore_test = struct
      type 'a t = Check of 'a | Ignore

      let _of_option = function None -> Ignore | Some x -> Check x

      let to_option = function Ignore -> None | Check x -> Some x

      let derived (x : ('input_type, 'b, _) Graphql_fields.Input.t) init :
          (_, _, _) Graphql_fields.Input.t =
        let open Graphql_fields in
        let opt = option x (o ()) in
        contramap ~f:to_option opt init

      (*
      module Args = struct
        let derived init =
          let open Graphql_args in
          let opt = option x (o ()) in
          map ~f:of_option opt init
      end
    *)
    end

    module T2 = struct
      type t = { foo : T1.t Or_ignore_test.t } [@@deriving fields]

      let v1 =
        { foo = Check { T1.foo_hello = Some 1; bar = [ "baz1"; "baz2" ] } }

      let v2 = { foo = Ignore }

      let manual_typ =
        Schema.(
          obj "T2" ?doc:None ~fields:(fun _ ->
              [ field "foo"
                  ~args:Arg.[]
                  ~typ:T1.manual_typ
                  ~resolve:(fun _ t -> Or_ignore_test.to_option t.foo)
              ]))

      let derived init =
        let open Graphql_fields in
        let ( !. ) x fd acc = add_field (x (o ())) fd acc in
        Fields.make_creator init
          ~foo:!.(Or_ignore_test.derived @@ T1.derived @@ o ())
        |> finish ~name:"T2" ?doc:None
    end

    let%test_unit "T2 fold" =
      let open Graphql_fields in
      let generated_typ =
        let typ_input = T2.(option @@ derived @@ o ()) (o ()) in
        !(typ_input#graphql_fields).run ()
      in
      [%test_eq: string]
        (hit_server generated_typ T2.v1)
        (hit_server T2.manual_typ T2.v1) ;
      [%test_eq: string]
        (hit_server generated_typ T2.v2)
        (hit_server T2.manual_typ T2.v2)
  end )
